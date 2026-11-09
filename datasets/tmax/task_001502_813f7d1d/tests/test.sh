#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

DYNAMIC_SERVER_PID=""
HASHER_REPLACED=0
cleanup() {
    if [ -n "$DYNAMIC_SERVER_PID" ]; then
        kill "$DYNAMIC_SERVER_PID" 2>/dev/null || true
    fi
    if [ "$HASHER_REPLACED" -eq 1 ] && [ -f /tmp/legacy_hasher.real ]; then
        rm -f /app/legacy_hasher
        mv /tmp/legacy_hasher.real /app/legacy_hasher
        chmod +x /app/legacy_hasher
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_original_state.py
import os
import requests
import time

def test_cron_file():
    cron_path = "/home/user/pipeline.cron"
    assert os.path.isfile(cron_path), f"Cron file not found: {cron_path}"
    with open(cron_path, "r") as f:
        content = f.read().strip()
    assert "/home/user/pipeline.py" in content, "Cron file does not execute /home/user/pipeline.py"
    parts = content.split()
    assert len(parts) >= 6, "Cron file format seems invalid."
    minute_field = parts[0]
    assert minute_field in ("*/15", "0,15,30,45"), f"Cron schedule is not every 15 minutes. Found: {minute_field}"
    lines = [line for line in content.splitlines() if line.strip()]
    assert len(lines) == 1, "Cron file must contain a single non-empty line"

def wait_for_server(url, timeout=5):
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = requests.get(url)
            if r.status_code in (200, 400, 404):
                return True
        except requests.exceptions.ConnectionError:
            time.sleep(0.5)
    return False

def test_api_u001():
    url = "http://127.0.0.1:8080/api/logs?user=U001"
    assert wait_for_server(url), "API server is not reachable at 127.0.0.1:8080"
    response = requests.get(url)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    data = response.json()
    assert "logs" in data, "Response JSON must contain a 'logs' key"
    logs = data["logs"]
    assert len(logs) == 1, f"Expected exactly 1 log for U001 after deduplication, got {len(logs)}"
    log = logs[0]
    assert log["timestamp"] == "2023-10-01T12:00:00Z", f"Incorrect timestamp: {log.get('timestamp')}"
    assert log["message"] == "First message", f"Incorrect message: {log.get('message')}"

def test_api_u002():
    url = "http://127.0.0.1:8080/api/logs?user=U002"
    assert wait_for_server(url), "API server is not reachable at 127.0.0.1:8080"
    response = requests.get(url)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    data = response.json()
    assert "logs" in data, "Response JSON must contain a 'logs' key"
    logs = data["logs"]
    assert len(logs) == 1, f"Expected exactly 1 log for U002, got {len(logs)}"
    log = logs[0]
    assert log["timestamp"] == "2023-10-01T13:00:00Z", f"Incorrect timestamp: {log.get('timestamp')}"
    assert log["message"] == "Line 1\nLine 2\nLine 3", f"Incorrect message, multi-line not preserved: {repr(log.get('message'))}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_state.py -x --tb=short 2>&1 || exit 1

[ -f /home/user/pipeline.py ] || { echo "pipeline.py is missing" >&2; exit 1; }
[ -f /home/user/server.py ] || { echo "server.py is missing" >&2; exit 1; }

python3 << 'PY' || exit 1
import csv
import datetime
import json
import random
import uuid

rng = random.SystemRandom()
base = 1704067200 + rng.randrange(0, 200 * 86400)
early = base - (base % 60)
mid = early + 1800
late = early + 7200
suffix = uuid.uuid4().hex[:10]
ua = "A_" + suffix
ub = "B_" + suffix
uc = "C_" + suffix

def iso(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def us(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%m/%d/%Y %H:%M:%S")

messages = {
    "late": "late-" + uuid.uuid4().hex,
    "duplicate": "must-not-survive-" + uuid.uuid4().hex,
    "multi": "first-" + suffix + "\nsecond-" + uuid.uuid4().hex + "\nthird",
    "early": "early-" + uuid.uuid4().hex,
    "collision": "collision-must-not-survive-" + uuid.uuid4().hex,
}
rows = [
    [str(late), ua, messages["late"]],
    [us(late), ua, messages["duplicate"]],
    [us(early), ub, messages["multi"]],
    [str(early), ua, messages["early"]],
    [str(mid), uc, messages["collision"]],
]
with open("/home/user/raw_logs.csv", "w", encoding="utf-16-le", newline="") as f:
    writer = csv.writer(f, lineterminator="\n")
    writer.writerow(["Timestamp", "UserID", "Message"])
    writer.writerows(rows)

keys = [
    f"{iso(late)}|{ua}",
    f"{iso(late)}|{ua}",
    f"{iso(early)}|{ub}",
    f"{iso(early)}|{ua}",
    f"{iso(mid)}|{uc}",
]
expected = {
    "users": {
        ua: [
            {"timestamp": iso(early), "message": messages["early"]},
            {"timestamp": iso(late), "message": messages["late"]},
        ],
        ub: [{"timestamp": iso(early), "message": messages["multi"]}],
        uc: [],
    },
    "calls": keys,
    "collision_keys": [keys[2], keys[4]],
}
with open("/tmp/dynamic_expected.json", "w") as f:
    json.dump(expected, f)
PY

rm -f /tmp/legacy_hasher_calls
: > /tmp/legacy_hasher_calls
chmod 666 /tmp/legacy_hasher_calls
mv /app/legacy_hasher /tmp/legacy_hasher.real || exit 1
HASHER_REPLACED=1
cat << 'HASH_EOF' > /app/legacy_hasher
#!/bin/bash
if [ "$#" -ne 1 ]; then
    exit 1
fi
printf '%s\n' "$1" >> /tmp/legacy_hasher_calls
if python3 - "$1" <<'PY'
import json, sys
with open('/tmp/dynamic_expected.json') as f:
    data = json.load(f)
raise SystemExit(0 if sys.argv[1] in data['collision_keys'] else 1)
PY
then
    printf '%s\n' '00000000000000000000000000000000'
    exit 0
fi
exec /tmp/legacy_hasher.real "$@"
HASH_EOF
chmod 755 /app/legacy_hasher

runuser -u user -- python3 /home/user/pipeline.py || exit 1

python3 << 'PY' || exit 1
import os, signal
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    try:
        raw = open(f'/proc/{name}/cmdline', 'rb').read()
        args = [x.decode(errors='ignore') for x in raw.split(b'\0') if x]
        if '/home/user/server.py' in args:
            os.kill(int(name), signal.SIGTERM)
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        pass
PY
sleep 1
runuser -u user -- sh -c 'nohup python3 /home/user/server.py >/tmp/dynamic_server.log 2>&1 & echo $!' > /tmp/dynamic_server.pid || exit 1
DYNAMIC_SERVER_PID=$(cat /tmp/dynamic_server.pid)

cat << 'TEST_EOF' > /tmp/test_dynamic_state.py
import json
import time
import requests

with open('/tmp/dynamic_expected.json') as f:
    EXPECTED = json.load(f)

def wait_for_server(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            response = requests.get('http://127.0.0.1:8080/api/logs?user=readiness', timeout=1)
            if response.status_code in (200, 400, 404):
                return
        except requests.RequestException:
            pass
        time.sleep(0.25)
    raise AssertionError('API server did not start after the pipeline was rerun')

def test_hasher_invoked_for_every_record_with_exact_normalized_key():
    with open('/tmp/legacy_hasher_calls') as f:
        calls = [line.rstrip('\n') for line in f]
    assert calls == EXPECTED['calls'], (
        'pipeline must invoke /app/legacy_hasher once per input record, in file order, '
        'with exactly NORMALIZED_TIMESTAMP|UserID'
    )

def test_dynamic_pipeline_and_api_results():
    wait_for_server()
    for user, expected_logs in EXPECTED['users'].items():
        response = requests.get('http://127.0.0.1:8080/api/logs', params={'user': user}, timeout=2)
        assert response.status_code == 200
        assert response.json() == {'logs': expected_logs}
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_state.py -x --tb=short 2>&1 || exit 1

echo "1" > /logs/verifier/reward.txt
exit 0
