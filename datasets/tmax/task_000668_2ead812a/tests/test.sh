#!/bin/bash
set +e
mkdir -p /logs/verifier
REWARD=/logs/verifier/reward.txt
echo "0" > "$REWARD"

GATEWAY_PID=""
CURL_REAL="/usr/bin/curl.verifier-real"
cleanup() {
    if [ -n "$GATEWAY_PID" ]; then
        kill -- -"$GATEWAY_PID" 2>/dev/null || true
        sleep 0.5
        kill -KILL -- -"$GATEWAY_PID" 2>/dev/null || true
    fi
    if [ -e "$CURL_REAL" ]; then
        rm -f /usr/bin/curl
        mv "$CURL_REAL" /usr/bin/curl
    fi
    if [ -e /tmp/aligner.py.original ]; then
        cp /tmp/aligner.py.original /app/aligner.py
    fi
    if [ -e /tmp/fft.py.original ]; then
        cp /tmp/fft.py.original /app/fft.py
    fi
}
trap cleanup EXIT

# The requested artifact must be a syntactically valid regular Bash script.
if ! python3 - <<'PY'
import os
import stat
import subprocess
import sys

path = "/home/user/gateway.sh"
try:
    st = os.lstat(path)
except FileNotFoundError:
    print("gateway.sh is missing")
    sys.exit(1)
if not stat.S_ISREG(st.st_mode):
    print("gateway.sh is not a regular file")
    sys.exit(1)
result = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
if result.returncode:
    print(result.stderr)
    sys.exit(1)
PY
then
    exit 0
fi

# Remove any services left by the agent so only gateway.sh can start the tested stack.
python3 - <<'PY'
import os
import signal
import time

ports = {5000, 5001, 8080}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        try:
            port = int(fields[1].rsplit(":", 1)[1], 16)
        except (IndexError, ValueError):
            continue
        if port in ports:
            inodes.add(fields[9])

ancestors = set()
pid = os.getpid()
while pid > 1:
    ancestors.add(pid)
    try:
        fields = open(f"/proc/{pid}/stat").read().split()
        pid = int(fields[3])
    except Exception:
        break

victims = set()
for name in os.listdir("/proc"):
    if not name.isdigit() or int(name) in ancestors or int(name) == 1:
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        fds = os.listdir(fd_dir)
    except OSError:
        continue
    for fd in fds:
        try:
            target = os.readlink(f"{fd_dir}/{fd}")
        except OSError:
            continue
        if target.startswith("socket:[") and target[8:-1] in inodes:
            victims.add(int(name))
            break
for victim in victims:
    try:
        os.kill(victim, signal.SIGKILL)
    except ProcessLookupError:
        pass
time.sleep(0.5)
PY

cp /app/aligner.py /tmp/aligner.py.original
cp /app/fft.py /tmp/fft.py.original
export VERIFIER_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
rm -f /tmp/aligner_requests.jsonl /tmp/fft_requests.jsonl /tmp/curl_calls.jsonl

# Preserve the original behavior for the original assertions, while adding a
# verifier-derived proof to unpredictable inputs and recording backend traffic.
cat > /app/aligner.py <<'PY'
from flask import Flask, request, jsonify
import hashlib
import json
import os

app = Flask(__name__)
SECRET = os.environ["VERIFIER_SECRET"]
FIXED = {"ATGC", "AAAA"}

@app.route('/align', methods=['POST'])
def align():
    seq = request.data.decode('utf-8')
    with open('/tmp/aligner_requests.jsonl', 'a') as f:
        f.write(json.dumps(seq) + '\n')
    result = {"score": len(seq) * 2}
    if seq not in FIXED and seq != "test":
        result["proof"] = hashlib.sha256((SECRET + ":align:" + seq).encode()).hexdigest()[:20]
    return jsonify(result)

if __name__ == '__main__':
    app.run(port=5000)
PY

cat > /app/fft.py <<'PY'
from flask import Flask, request, jsonify
import hashlib
import json
import os

app = Flask(__name__)
SECRET = os.environ["VERIFIER_SECRET"]
FIXED = {"ATGC", "AAAA"}

@app.route('/spectrum', methods=['POST'])
def spectrum():
    seq = request.data.decode('utf-8')
    with open('/tmp/fft_requests.jsonl', 'a') as f:
        f.write(json.dumps(seq) + '\n')
    if len(set(seq)) == 1:
        return "Internal Server Error", 500
    result = {"dominant_freq": 0.33}
    if seq not in FIXED and seq != "test":
        result["proof"] = hashlib.sha256((SECRET + ":fft:" + seq).encode()).hexdigest()[:20]
    return jsonify(result)

if __name__ == '__main__':
    app.run(port=5001)
PY

# Wrap the system curl so successful verification also proves that gateway.sh
# actually invoked curl, rather than merely imitating the backend responses.
if [ ! -e /usr/bin/curl ]; then
    echo "curl is missing"
    exit 0
fi
mv /usr/bin/curl "$CURL_REAL"
cat > /usr/bin/curl <<'SH'
#!/bin/bash
python3 - "$@" <<'PY'
import json
import sys
with open('/tmp/curl_calls.jsonl', 'a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\n')
PY
exec /usr/bin/curl.verifier-real "$@"
SH
chmod 755 /usr/bin/curl

setsid bash /home/user/gateway.sh >/tmp/gateway-verifier.log 2>&1 &
GATEWAY_PID=$!

cat > /tmp/test_final_state.py <<'PY'
import hashlib
import json
import os
import random
import secrets
import time

import pytest
import requests

GATEWAY_URL = "http://127.0.0.1:8080/analyze"
SECRET = os.environ["VERIFIER_SECRET"]
TESTED_SEQUENCES = []


def wait_for_service(url, timeout=10):
    """Wait for the gateway service to become available."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.post(url, data="test", timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    return False


def post_sequence(seq):
    TESTED_SEQUENCES.append(seq)
    try:
        return requests.post(GATEWAY_URL, data=seq, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to gateway: {e}")


def test_gateway_normal_sequence():
    """Test that the gateway handles a normal sequence correctly."""
    assert wait_for_service(GATEWAY_URL), "Gateway service is not running or not listening on port 8080."

    seq = "ATGC"
    response = post_sequence(seq)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "alignment" in data, "Response JSON missing 'alignment' key."
    assert "spectrum" in data, "Response JSON missing 'spectrum' key."
    assert data["alignment"] == {"score": 8}, f"Expected alignment score 8, got {data['alignment']}"
    assert data["spectrum"] == {"dominant_freq": 0.33}, f"Expected spectrum dominant_freq 0.33, got {data['spectrum']}"


def test_gateway_singular_sequence():
    """Test that the gateway handles a singular sequence (fallback) correctly."""
    assert wait_for_service(GATEWAY_URL), "Gateway service is not running or not listening on port 8080."

    seq = "AAAA"
    response = post_sequence(seq)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "alignment" in data, "Response JSON missing 'alignment' key."
    assert "error" in data, "Response JSON missing 'error' key."
    assert data["error"] == "near-singular sequence detected", f"Unexpected error message: {data['error']}"
    assert data["alignment"] == {"score": 8}, f"Expected alignment score 8, got {data['alignment']}"
    assert "spectrum" not in data, "Response JSON should not contain 'spectrum' on fallback."


def test_unpredictable_sequences_are_forwarded_and_combined():
    rng = random.SystemRandom()
    normal = []
    while len(normal) < 4:
        seq = ''.join(rng.choice('ACGT') for _ in range(rng.randint(7, 31)))
        if len(set(seq)) > 1 and seq not in normal:
            normal.append(seq)

    for seq in normal:
        response = post_sequence(seq)
        assert response.status_code == 200
        data = response.json()
        expected_alignment = {
            "score": len(seq) * 2,
            "proof": hashlib.sha256((SECRET + ":align:" + seq).encode()).hexdigest()[:20],
        }
        expected_spectrum = {
            "dominant_freq": 0.33,
            "proof": hashlib.sha256((SECRET + ":fft:" + seq).encode()).hexdigest()[:20],
        }
        assert data["alignment"] == expected_alignment
        assert data["spectrum"] == expected_spectrum


def test_unpredictable_singular_sequences_use_fallback():
    singular = []
    for _ in range(3):
        base = secrets.choice('ACGT')
        seq = base * random.SystemRandom().randint(8, 35)
        while seq in singular or seq == "AAAA":
            seq = base * random.SystemRandom().randint(8, 35)
        singular.append(seq)

    for seq in singular:
        response = post_sequence(seq)
        assert response.status_code == 200
        data = response.json()
        expected_alignment = {
            "score": len(seq) * 2,
            "proof": hashlib.sha256((SECRET + ":align:" + seq).encode()).hexdigest()[:20],
        }
        assert data["alignment"] == expected_alignment
        assert data["error"] == "near-singular sequence detected"
        assert "spectrum" not in data


def test_backends_and_curl_were_really_used():
    def load_requests(path):
        with open(path) as f:
            return [json.loads(line) for line in f if line.strip()]

    align_requests = load_requests('/tmp/aligner_requests.jsonl')
    fft_requests = load_requests('/tmp/fft_requests.jsonl')
    for seq in TESTED_SEQUENCES:
        assert seq in align_requests, f"aligner backend did not receive {seq!r}"
        assert seq in fft_requests, f"FFT backend did not receive {seq!r}"

    with open('/tmp/curl_calls.jsonl') as f:
        calls = [json.loads(line) for line in f if line.strip()]
    align_calls = [args for args in calls if 'http://127.0.0.1:5000/align' in args]
    fft_calls = [args for args in calls if 'http://127.0.0.1:5001/spectrum' in args]
    assert len(align_calls) >= len(TESTED_SEQUENCES)
    assert len(fft_calls) >= len(TESTED_SEQUENCES)
PY

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > "$REWARD"
else
    echo "0" > "$REWARD"
fi
exit 0
