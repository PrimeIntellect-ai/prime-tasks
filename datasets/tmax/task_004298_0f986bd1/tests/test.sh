#!/bin/bash
set -e
mkdir -p /logs/verifier

if (
set -e

# Preserve the original final-state assertions.
python3 - <<'PY'
import os

alerts = "/home/user/logs/alerts.log"
assert os.path.exists(alerts), f"File {alerts} does not exist."
assert os.path.isfile(alerts), f"Path {alerts} is not a file."
with open(alerts, encoding="utf-8") as f:
    actual = {line.strip() for line in f if line.strip()}
expected = {"../../etc/passwd", "/var/log/syslog"}
assert expected.issubset(actual), f"Expected malicious paths {expected} not found in {alerts}. Found: {actual}"

safe = "/home/user/logs/safe.log"
assert os.path.exists(safe), f"File {safe} does not exist."
assert os.path.isfile(safe), f"Path {safe} is not a file."
with open(safe, encoding="utf-8") as f:
    actual = {line.strip() for line in f if line.strip()}
expected = {"valid_data_1.csv", "valid_data_2.txt"}
assert expected.issubset(actual), f"Expected safe paths {expected} not found in {safe}. Found: {actual}"

c_path = "/home/user/workspace/safepipe.c"
exe_path = "/home/user/workspace/safepipe"
script_path = "/home/user/workspace/monitor.sh"
assert os.path.exists(c_path) and os.path.isfile(c_path), f"File {c_path} does not exist or is not a file."
assert os.path.exists(exe_path) and os.path.isfile(exe_path), f"File {exe_path} does not exist or is not a file."
assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
assert os.path.exists(script_path) and os.path.isfile(script_path), f"File {script_path} does not exist or is not a file."
PY

# The submitted source must compile as C, and the installed artifact must be a
# compiled executable rather than an arbitrary placeholder script.
gcc -std=c11 -Wall -Wextra -o /tmp/safepipe_from_source /home/user/workspace/safepipe.c
python3 - <<'PY'
with open('/home/user/workspace/safepipe', 'rb') as f:
    assert f.read(4) == b'\x7fELF', 'safepipe is not a compiled ELF executable'
PY

# Exercise both the installed binary and a fresh build from the submitted source
# on unpredictable paths, deriving the expected routing from the stated rule.
python3 - <<'PY'
import os
import subprocess
import uuid

alert_path = '/home/user/logs/alerts.log'
token = uuid.uuid4().hex
paths = [
    f'{token}.csv',
    '..',
    f'dir/{token}/file.txt',
    f'prefix/../{token}',
    f'../{token}/secret',
    f'/{token}/absolute',
    f'name..part/{token}',
]
safe = [p for p in paths if '../' not in p and not p.startswith('/')]
malicious = [p for p in paths if '../' in p or p.startswith('/')]
input_data = ''.join(p + '\n' for p in paths)

for executable in ['/home/user/workspace/safepipe', '/tmp/safepipe_from_source']:
    os.makedirs('/home/user/logs', exist_ok=True)
    with open(alert_path, 'w', encoding='utf-8') as f:
        f.write('preexisting-marker\n')
    result = subprocess.run(
        [executable], input=input_data, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert result.returncode == 0, f'{executable} failed: {result.stderr}'
    assert result.stdout.splitlines() == safe, (
        f'{executable} emitted incorrect safe paths: {result.stdout.splitlines()}'
    )
    with open(alert_path, encoding='utf-8') as f:
        logged = f.read().splitlines()
    assert logged == ['preexisting-marker'] + malicious, (
        f'{executable} did not append exactly the malicious paths: {logged}'
    )
PY

# Stop any watcher left by the agent so this test specifically launches the
# submitted monitor.sh, then create a fresh unpredictable two-part archive.
pkill -f '^bash /home/user/workspace/monitor.sh$' 2>/dev/null || true
pkill -f '^/bin/bash /home/user/workspace/monitor.sh$' 2>/dev/null || true
rm -rf /home/user/incoming
mkdir -p /home/user/incoming /home/user/logs /home/user/workspace
rm -f /home/user/logs/alerts.log /home/user/logs/safe.log
rm -f /home/user/workspace/payload.tar.gz
rm -rf /tmp/verifier_stage
mkdir -p /tmp/verifier_stage

python3 - <<'PY'
import io
import json
import os
import tarfile
import uuid

stage = '/tmp/verifier_stage'
token = uuid.uuid4().hex
safe = [f'safe_{token}.csv', f'nested/data_{token}.txt']
malicious = [f'../../../tmp/traversal_{token}', f'/tmp/absolute_{token}']

payload = os.path.join(stage, 'payload.tar.gz')
with tarfile.open(payload, 'w:gz') as tf:
    for name in safe + malicious:
        info = tarfile.TarInfo(name)
        data = (token + '\n').encode()
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))

outer = os.path.join(stage, 'dump.tar')
with tarfile.open(outer, 'w') as tf:
    tf.add(payload, arcname='payload.tar.gz')

with open(outer, 'rb') as f:
    data = f.read()
cut = len(data) // 2
with open(os.path.join(stage, 'dump.tar.aa'), 'wb') as f:
    f.write(data[:cut])
with open(os.path.join(stage, 'dump.tar.ab'), 'wb') as f:
    f.write(data[cut:])

with open(os.path.join(stage, 'expect.json'), 'w') as f:
    json.dump({'safe': safe, 'malicious': malicious}, f)
PY

# Start the actual watcher, allow inotifywait to initialize, and deliver the two
# parts in the required order. A timeout prevents a defective watcher hanging the verifier.
timeout 20s bash /home/user/workspace/monitor.sh >/tmp/monitor.stdout 2>/tmp/monitor.stderr &
MONITOR_PID=$!
sleep 1
cp /tmp/verifier_stage/dump.tar.aa /home/user/incoming/dump.tar.aa
sleep 0.2
cp /tmp/verifier_stage/dump.tar.ab /home/user/incoming/dump.tar.ab

for _ in $(seq 1 60); do
    if [ -f /home/user/workspace/payload.tar.gz ] && \
       [ -s /home/user/logs/safe.log ] && [ -s /home/user/logs/alerts.log ]; then
        break
    fi
    sleep 0.25
done
sleep 0.5
kill "$MONITOR_PID" 2>/dev/null || true
wait "$MONITOR_PID" 2>/dev/null || true
pkill -f '^inotifywait .* /home/user/incoming' 2>/dev/null || true

python3 - <<'PY'
import json
import os

with open('/tmp/verifier_stage/expect.json') as f:
    expected = json.load(f)

payload = '/home/user/workspace/payload.tar.gz'
assert os.path.isfile(payload), 'monitor did not extract payload.tar.gz from the concatenated outer archive'

for path in ['/home/user/logs/safe.log', '/home/user/logs/alerts.log']:
    assert os.path.isfile(path), f'{path} was not produced by the pipeline'

with open('/home/user/logs/safe.log', encoding='utf-8') as f:
    safe = [line.strip() for line in f if line.strip()]
with open('/home/user/logs/alerts.log', encoding='utf-8') as f:
    malicious = [line.strip() for line in f if line.strip()]

assert set(safe) == set(expected['safe']), f'incorrect safe.log from monitor pipeline: {safe}'
assert set(malicious) == set(expected['malicious']), f'incorrect alerts.log from monitor pipeline: {malicious}'
assert len(safe) == len(expected['safe']), f'duplicate or extra safe entries: {safe}'
assert len(malicious) == len(expected['malicious']), f'duplicate or extra malicious entries: {malicious}'

# The nested archive must only have been listed, never extracted.
for name in expected['malicious']:
    resolved = os.path.normpath(os.path.join('/home/user/workspace', name)) if not name.startswith('/') else name
    assert not os.path.exists(resolved), f'malicious nested member was extracted: {resolved}'
for name in expected['safe']:
    resolved = os.path.normpath(os.path.join('/home/user/workspace', name))
    assert not os.path.exists(resolved), f'nested payload member was extracted: {resolved}'
PY

); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
