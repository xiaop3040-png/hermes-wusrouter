#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
BASE_URL="${WUS_BASE_URL:-https://wusrouter.com/v1}"
HERMES_DIR="${HERMES_HOME:-$HOME/.hermes}"
BACKUP_DIR=''
CHANGED=0
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
rollback() {
  local code=$?
  if (( code != 0 && CHANGED == 1 )); then
    echo "[ERROR] Setup failed; restoring config backup..." >&2
    for f in config.yaml .env; do
      if [[ -f "$BACKUP_DIR/$f" ]]; then cp -p "$BACKUP_DIR/$f" "$HERMES_DIR/$f"; else rm -f "$HERMES_DIR/$f"; fi
    done
    echo "Restored from $BACKUP_DIR" >&2
  fi
  cleanup
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for cmd in hermes curl python3; do command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 1; }; done
[[ "$BASE_URL" == https://* ]] || { echo 'Only HTTPS endpoints are accepted.' >&2; exit 1; }
[[ -t 0 ]] || { echo 'Interactive terminal required. Run: bash <(curl -fsSL URL)' >&2; exit 1; }
printf 'WusRouter API key: '
IFS= read -rs API_KEY; printf '\n'
[[ -n "$API_KEY" && "$API_KEY" != *$'\n'* ]] || { echo 'Invalid or empty key.' >&2; exit 1; }
printf '[INFO] Checking /models ...\n'
HTTP_CODE="$(curl --silent --show-error --max-time 20 --output "$TMP_DIR/models.json" --write-out '%{http_code}' --header "Authorization: Bearer $API_KEY" "$BASE_URL/models")" || { echo 'Network error contacting router.' >&2; exit 1; }
if [[ "$HTTP_CODE" != 200 ]]; then
  echo "Router returned HTTP $HTTP_CODE. Response:" >&2
  head -c 500 "$TMP_DIR/models.json" >&2; echo >&2
  exit 1
fi
python3 - "$TMP_DIR/models.json" "$TMP_DIR/ids.txt" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1])); ids=[m['id'] for m in d['data'] if isinstance(m,dict) and isinstance(m.get('id'),str)]
    if not ids: raise ValueError('No model IDs returned')
    open(sys.argv[2],'w').write('\n'.join(ids)+'\n')
except Exception as e: sys.exit('Invalid /models response: '+str(e))
PY
printf '\nAvailable models (first 30):\n'
head -n 30 "$TMP_DIR/ids.txt" | nl -w2 -s'. '
printf '\nEnter exact Model ID (or number from list): '
IFS= read -r MODEL_INPUT
[[ -n "$MODEL_INPUT" ]] || { echo 'Model required.' >&2; exit 1; }
if [[ "$MODEL_INPUT" =~ ^[0-9]+$ ]]; then
  MODEL="$(sed -n "${MODEL_INPUT}p" "$TMP_DIR/ids.txt")"
else MODEL="$MODEL_INPUT"; fi
[[ -n "$MODEL" ]] || { echo 'Invalid model selection.' >&2; exit 1; }
if ! grep -Fxq -- "$MODEL" "$TMP_DIR/ids.txt"; then echo 'Model ID not in router catalog.' >&2; exit 1; fi
mkdir -p "$HERMES_DIR/backups"
BACKUP_DIR="$HERMES_DIR/backups/wusrouter-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -m 700 "$BACKUP_DIR"
for f in config.yaml .env; do [[ ! -f "$HERMES_DIR/$f" ]] || cp -p "$HERMES_DIR/$f" "$BACKUP_DIR/$f"; done
CHANGED=1
hermes config set WUSTEAM_API_KEY "$API_KEY" >/dev/null
hermes config set model.provider custom >/dev/null
hermes config set model.base_url "$BASE_URL" >/dev/null
hermes config set model.key_env WUSTEAM_API_KEY >/dev/null
hermes config set model.default "$MODEL" >/dev/null
[[ ! -f "$HERMES_DIR/.env" ]] || chmod 600 "$HERMES_DIR/.env"
[[ ! -f "$HERMES_DIR/config.yaml" ]] || chmod 600 "$HERMES_DIR/config.yaml"
actual="$(hermes config get model.default --raw 2>/dev/null)"
[[ "$actual" == "$MODEL" ]] || { echo 'Config verification failed.' >&2; exit 1; }
CHANGED=0
unset API_KEY
printf '\n[SUCCESS] Hermes configured for WusRouter.\nEndpoint: %s\nModel: %s\nBackup: %s\n' "$BASE_URL" "$MODEL" "$BACKUP_DIR"
printf '\nRun: hermes chat\n'
printf 'Optional live inference test (may incur charges): start Hermes chat and send a short prompt.\n'
