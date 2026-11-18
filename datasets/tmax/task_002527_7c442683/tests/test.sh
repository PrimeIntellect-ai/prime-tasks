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

run_checks() {
    cd /home/user/voicemail-api || return 1

    python3 - <<'PY' || return 1
import json
import os
import re
import subprocess
import requests

repo = "/home/user/voicemail-api"
token_path = "/home/user/token.txt"
transcript_path = "/home/user/transcript.log"
wav_path = "/app/voicemail.wav"
expected_token = "sup3r_s3cr3t_v2_f0r3ns1cs"
expected_transcript = "System alert core router temperature critical"

assert os.path.isfile(token_path), f"Expected {token_path} to exist"
with open(token_path) as f:
    token = f.read().strip()
assert token == expected_token, f"Token file content incorrect: {token!r}"

assert os.path.isfile(transcript_path), f"Expected {transcript_path} to exist"
with open(transcript_path) as f:
    transcript = f.read().strip()
assert transcript == expected_transcript, f"Transcript file content incorrect: {transcript!r}"

assert os.path.isdir(os.path.join(repo, ".git")), "The supplied git repository is missing"
history = subprocess.check_output(
    ["git", "-C", repo, "log", "-p", "--all", "--", "main.go", "processor.go"],
    text=True,
)
recovered = set(re.findall(r'authSecret\s*=\s*"([^"]+)"', history))
assert expected_token in recovered, "The token file does not match the hardcoded token recoverable from git history"

processor_path = os.path.join(repo, "processor.go")
assert os.path.isfile(processor_path), "processor.go was not created/fixed"
with open(processor_path) as f:
    processor_source = f.read()
assert re.search(r'type\s+Processor\s+struct', processor_source), "Processor must be defined in processor.go"
assert re.search(r'func\s*\([^)]*\*Processor[^)]*\)\s*Transcribe\s*\(', processor_source), "Processor.Transcribe must be implemented in processor.go"

sources = ""
for name in os.listdir(repo):
    if name.endswith(".go") and not name.endswith("_test.go"):
        with open(os.path.join(repo, name)) as f:
            sources += "\n" + f.read()
assert "/api/v1/transcribe" in sources and re.search(r'\.Transcribe\b', sources), "The service must route the API endpoint to Processor.Transcribe"

with open(os.path.join(repo, "go.mod")) as f:
    gomod = f.read()
assert re.search(r'github\.com/sirupsen/logrus\s+v1\.9\.0\b', gomod), "Logger dependency was not preserved"
assert re.search(r'github\.com/google/uuid\s+v1\.3\.0\b', gomod), "The conflicting audio-stub dependency was not resolved to v1.3.0"

assert os.path.isfile(wav_path), "Emergency voicemail is missing"
with open(wav_path, "rb") as f:
    audio = f.read()
url = "http://127.0.0.1:8080/api/v1/transcribe"

# Preserve the checks against the service the agent started.
r = requests.post(url, headers={"Authorization": "Bearer invalid_token"}, timeout=2)
assert r.status_code == 401, f"Expected 401 for invalid token, got {r.status_code}"
for _ in range(2):
    r = requests.post(url, headers={"Authorization": "Bearer " + token}, data=audio, timeout=5)
    assert r.status_code == 200, f"Expected 200 for valid token, got {r.status_code}"
    assert r.json().get("transcript") == expected_transcript, f"Unexpected transcription: {r.text}"
PY

    # The submitted Go project itself must resolve and build without modifying go.mod.
    go build -mod=readonly -o /tmp/voicemail-api-verifier . || return 1
    test -x /tmp/voicemail-api-verifier || return 1

    # Replace the agent-started process with the artifact built from the submitted source,
    # ensuring subsequent behavioral checks cannot be satisfied by an unrelated tiny server.
    python3 - <<'PY' || return 1
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

for entry in os.listdir("/proc"):
    if not entry.isdigit():
        continue
    fd_dir = f"/proc/{entry}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                try:
                    os.kill(int(entry), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except (FileNotFoundError, PermissionError):
        pass
time.sleep(1)
PY

    TOKEN=$(cat /home/user/token.txt) || return 1
    nohup env API_TOKEN="$TOKEN" /tmp/voicemail-api-verifier >/tmp/voicemail-api-verifier.log 2>&1 &
    SERVICE_PID=$!
    export SERVICE_PID

    python3 - <<'PY' || return 1
import os
import time
import requests

url = "http://127.0.0.1:8080/api/v1/transcribe"
for _ in range(50):
    try:
        requests.post(url, timeout=0.2)
        break
    except requests.RequestException:
        time.sleep(0.1)
else:
    raise AssertionError("Built Go service did not start on 127.0.0.1:8080")

pid = os.environ["SERVICE_PID"]
socket_inodes = set()
for fd in os.listdir(f"/proc/{pid}/fd"):
    try:
        target = os.readlink(f"/proc/{pid}/fd/{fd}")
    except OSError:
        continue
    if target.startswith("socket:["):
        socket_inodes.add(target[8:-1])

bound_exactly = False
with open("/proc/net/tcp") as f:
    next(f)
    for line in f:
        fields = line.split()
        if fields[9] in socket_inodes and fields[3] == "0A" and fields[1].upper() == "0100007F:1F90":
            bound_exactly = True
            break
assert bound_exactly, "Built service is not listening exactly on 127.0.0.1:8080"
PY

    # Exercise the built service under actual simultaneous contention.
    python3 - <<'PY' || return 1
import concurrent.futures
import os
import secrets
import threading
import requests

url = "http://127.0.0.1:8080/api/v1/transcribe"
with open("/home/user/token.txt") as f:
    token = f.read().strip()
with open("/app/voicemail.wav", "rb") as f:
    audio = f.read()
expected = "System alert core router temperature critical"

# Missing and independently generated invalid credentials must be rejected.
r = requests.post(url, data=audio, timeout=2)
assert r.status_code == 401, f"Expected 401 without authorization, got {r.status_code}"
for _ in range(4):
    invalid = secrets.token_urlsafe(24)
    assert invalid != token
    r = requests.post(url, headers={"Authorization": "Bearer " + invalid}, data=audio, timeout=2)
    assert r.status_code == 401, f"Expected 401 for generated invalid token, got {r.status_code}"

workers = 16
barrier = threading.Barrier(workers)
def transcribe(_):
    barrier.wait(timeout=3)
    response = requests.post(
        url,
        headers={"Authorization": "Bearer " + token},
        data=audio,
        timeout=8,
    )
    return response.status_code, response.json()

with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
    futures = [pool.submit(transcribe, i) for i in range(workers)]
    results = [f.result(timeout=10) for f in futures]

for status, body in results:
    assert status == 200, f"Concurrent request returned {status}"
    assert body.get("transcript") == expected, f"Unexpected concurrent transcription: {body}"
PY

    kill -0 "$SERVICE_PID" 2>/dev/null || return 1
    return 0
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
