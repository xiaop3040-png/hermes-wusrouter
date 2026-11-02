#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
BASE_URL="${WUS_BASE_URL:-https://wusrouter.com}"
for dep in curl python3 claude; do command -v "$dep" >/dev/null || { echo "Missing: $dep" >&2; exit 1; }; done
[[ -r /dev/tty && -w /dev/tty ]] || { echo "Interactive terminal required" >&2; exit 1; }
printf "WusTeam API key: " >/dev/tty
IFS= read -rs KEY </dev/tty
printf '\n' >/dev/tty
[[ -n "$KEY" ]] || { echo "Empty key" >&2; exit 1; }
TMP="$(mktemp)"
trap 'rm -f "$TMP"; unset KEY' EXIT
STATUS="$(curl -fsS --max-time 20 -o "$TMP" -w '%{http_code}' -H "Authorization: Bearer $KEY" "$BASE_URL/v1/models")" || { echo "Cannot fetch model catalog" >&2; exit 1; }
[[ "$STATUS" == 200 ]] || { echo "HTTP $STATUS" >&2; exit 1; }
python3 - "$TMP" <<'PY'
import json,sys
models=json.load(open(sys.argv[1])).get('data',[])
for m in models:
 if isinstance(m,dict) and 'glm' in str(m.get('id','')).lower():
  print(m['id'], ' | ',m.get('name',m.get('display_name','')))
PY
printf 'Exact GLM 5.3 Flash model ID: ' >/dev/tty
IFS= read -r FLASH </dev/tty
printf 'Exact GLM 5.3 Flash Premium model ID: ' >/dev/tty
IFS= read -r PREMIUM </dev/tty
[[ -n "$FLASH" && -n "$PREMIUM" ]] || { echo "Both model IDs required" >&2; exit 1; }
export FLASH PREMIUM KEY BASE_URL
python3 - "$TMP" <<'PY'
import json,os,pathlib,shutil,datetime,tempfile,sys
ids={m.get('id') for m in json.load(open(sys.argv[1])).get('data',[]) if isinstance(m,dict)}
for k in ('FLASH','PREMIUM'):
 if os.environ[k] not in ids: sys.exit('Model ID not found in /models: '+os.environ[k])
p=pathlib.Path.home()/'.claude'/'settings.json'
p.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
data=json.loads(p.read_text()) if p.exists() else {}
if not isinstance(data,dict) or not isinstance(data.get('env',{}),dict): sys.exit('Unexpected Claude settings structure')
env=data.setdefault('env',{})
env.update({'ANTHROPIC_BASE_URL':os.environ['BASE_URL'],'ANTHROPIC_AUTH_TOKEN':os.environ['KEY'],'ANTHROPIC_API_KEY':'','ANTHROPIC_MODEL':os.environ['FLASH'],'ANTHROPIC_DEFAULT_SONNET_MODEL':os.environ['FLASH'],'ANTHROPIC_DEFAULT_OPUS_MODEL':os.environ['PREMIUM']})
if p.exists():
 b=p.with_name('settings.json.bak-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S'))
 shutil.copy2(p,b)
 print('Backup:',b)
fd,tmp=tempfile.mkstemp(dir=p.parent,prefix='.settings-')
try:
 with os.fdopen(fd,'w') as f: json.dump(data,f,indent=2); f.write('\n')
 os.chmod(tmp,0o600)
 os.replace(tmp,p)
finally:
 if os.path.exists(tmp): os.unlink(tmp)
print('Configured:',p)
print('Default GLM:',os.environ['FLASH'])
print('Premium via: claude --model opus')
PY
unset KEY
echo 'Note: Model listing does not prove Anthropic Messages compatibility. A real prompt may incur charges.'
