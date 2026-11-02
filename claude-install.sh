#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

BASE_URL="https://wusrouter.com"
MODEL="${WUS_MODEL:-claude-opus-5}"
[[ "$MODEL" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Invalid model ID" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl required" >&2; exit 1; }
[[ -r /dev/tty && -w /dev/tty ]] || { echo "Interactive terminal required" >&2; exit 1; }
if ! command -v claude >/dev/null; then
  echo "Claude Code not installed. Install official CLI first: curl -fsSL https://claude.ai/install.sh | bash" >&2
  exit 1
fi
printf "WusTeam API key: " > /dev/tty
IFS= read -r -s KEY < /dev/tty
printf "\n" > /dev/tty
[[ -n "$KEY" ]] || { echo "Empty API key" >&2; exit 1; }
tmp="$(mktemp)"
trap 'rm -f "$tmp"; unset KEY' EXIT
code="$(curl -sS --max-time 20 -o "$tmp" -w '%{http_code}' -H "Authorization: Bearer $KEY" "$BASE_URL/v1/models")" || { echo "Router unreachable" >&2; exit 1; }
[[ "$code" == 200 ]] || { echo "Router /models returned HTTP $code" >&2; exit 1; }
if ! python3 - "$tmp" "$MODEL" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
ids=[m.get("id") for m in data.get("data",[]) if isinstance(m,dict)]
if sys.argv[2] not in ids:
    print("Model not listed by router:",sys.argv[2],file=sys.stderr)
    sys.exit(1)
PY
then exit 1; fi
mkdir -p "$HOME/.claude"
chmod 700 "$HOME/.claude"
export WUS_KEY="$KEY" WUS_MODEL="$MODEL" WUS_URL="$BASE_URL"
python3 - <<'PY'
import json,os,pathlib,tempfile
p=pathlib.Path.home()/".claude"/"settings.json"
data=json.loads(p.read_text()) if p.exists() else {}
if not isinstance(data,dict): raise ValueError("Invalid existing settings")
env=data.setdefault("env",{})
if not isinstance(env,dict): raise ValueError("Invalid existing env")
env.update({
 "ANTHROPIC_BASE_URL":os.environ["WUS_URL"],
 "ANTHROPIC_AUTH_TOKEN":os.environ["WUS_KEY"],
 "ANTHROPIC_API_KEY":"",
 "ANTHROPIC_MODEL":os.environ["WUS_MODEL"]
})
if p.exists():
 import shutil,datetime
 backup=p.with_name("settings.json.bak-"+datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S"))
 shutil.copy2(p,backup)
 print("Backup:",backup)
fd,name=tempfile.mkstemp(dir=str(p.parent),prefix=".settings-",text=True)
try:
 with os.fdopen(fd,"w") as f: json.dump(data,f,indent=2); f.write("\n")
 os.chmod(name,0o600)
 os.replace(name,p)
finally:
 if os.path.exists(name): os.unlink(name)
print("Saved:",p)
PY
unset WUS_KEY KEY
echo "Configured Claude Code for WusTeam ($MODEL). Run: claude"
echo "Note: /models checks availability only, not Anthropic Messages compatibility or model authenticity."
