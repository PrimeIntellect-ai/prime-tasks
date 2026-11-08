#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import csv
import glob
import json
import math
import os
import random
import re
import signal
import subprocess
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8000"


def request(path):
    try:
        with urllib.request.urlopen(BASE + path, timeout=2) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def wait_for(path, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            status, _ = request(path)
            if status in (200, 404):
                return True
        except Exception:
            pass
        time.sleep(0.25)
    return False


def assert_result(record_id, expected):
    status, body = request(f"/result/{record_id}")
    assert status == 200, f"Expected status 200 for ID {record_id}, got {status}"
    data = json.loads(body.decode("utf-8"))
    assert data.get("id") == record_id, f"Expected id {record_id}, got {data.get('id')}"
    assert isinstance(data.get("result"), (int, float)), "result must be numeric"
    assert math.isclose(float(data["result"]), float(expected), rel_tol=0, abs_tol=1e-9), \
        f"Expected result {expected}, got {data.get('result')}"


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F40" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    found = []
    for proc_dir in glob.glob("/proc/[0-9]*"):
        pid = int(proc_dir.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(proc_dir + "/fd"):
                target = os.readlink(proc_dir + "/fd/" + fd)
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    found.append(pid)
                    break
        except (OSError, PermissionError):
            pass
    return sorted(set(found))


# A Python implementation artifact must exist, and the originally requested server
# must already be running.
python_files = [p for p in glob.glob("/app/**/*.py", recursive=True) if os.path.isfile(p) and os.path.getsize(p) > 0]
assert python_files, "No nonempty Python pipeline/server implementation was found under /app"
assert wait_for("/result/101", 5), "API server is not reachable at 127.0.0.1:8000"

# Preserve all original API assertions.
assert_result(101, -38.0)
assert_result(102, -37.0)
assert_result(103, -30.0)
status, _ = request("/result/999")
assert status == 404, f"Expected status 404 for ID 999, got {status}"

# Preserve the original log assertions.
log_path = "/app/pipeline.log"
assert os.path.exists(log_path), f"Log file not found at {log_path}"
assert os.path.isfile(log_path), f"Path {log_path} is not a file"
with open(log_path, "r", encoding="utf-8") as handle:
    original_log = handle.read()
assert original_log.strip(), "Log file is empty"
assert "-" in original_log and ":" in original_log, "Log file does not appear to use a standard logging format"

# Capture the actual command serving port 8000 so that the submitted artifact can
# be rerun against verifier-generated inputs.
pids = listener_pids()
assert pids, "Could not identify the process listening on port 8000"
server_pid = pids[0]
with open(f"/proc/{server_pid}/cmdline", "rb") as handle:
    argv = [part.decode("utf-8") for part in handle.read().split(b"\0") if part]
assert argv, "Listening server has no executable command line"
server_cwd = os.readlink(f"/proc/{server_pid}/cwd")

# Generate a new spoken operation unknown while the agent was running.
amount, amount_word = random.choice([(11, "eleven"), (13, "thirteen"), (17, "seventeen"), (19, "nineteen")])
tmp_wav = "/app/.verifier_instruction.wav"
subprocess.run(
    ["espeak", "-w", tmp_wav, f"Add {amount_word} to all results."],
    check=True,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
os.replace(tmp_wav, "/app/instruction.wav")

# Use unpredictable IDs, several Unicode numeric forms, and one malformed row that
# the required error logging must report.
base_id = random.SystemRandom().randrange(20000, 90000)
valid_rows = [
    (base_id, "⑧ * ５", 40.0),
    (base_id + 7, "Ⅳ + ½", 4.5),
    (base_id + 19, "⑳ / ５", 4.0),
]
bad_id = base_id + 31
with open("/app/math_data.csv", "w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(["id", "expression"])
    for record_id, expression, _ in valid_rows:
        writer.writerow([record_id, expression])
    writer.writerow([bad_id, "⑧ ? ２"])

# Ensure all dynamic evidence comes from this execution.
with open(log_path, "w", encoding="utf-8"):
    pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

deadline = time.time() + 3
while time.time() < deadline and listener_pids():
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.1)

server_output = open("/tmp/submission-server.log", "ab", buffering=0)
proc = subprocess.Popen(argv, cwd=server_cwd, stdout=server_output, stderr=subprocess.STDOUT)
try:
    assert wait_for(f"/result/{base_id}", 12), "Submitted server did not restart on verifier-generated inputs"

    for record_id, _, raw_value in valid_rows:
        assert_result(record_id, raw_value + amount)

    status, _ = request(f"/result/{bad_id}")
    assert status == 404, f"Malformed record ID {bad_id} should not produce a result; got status {status}"

    with open(log_path, "r", encoding="utf-8") as handle:
        content = handle.read()
    lower = content.lower()
    assert re.search(r"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\s*-\s*[A-Z]+\s*-", content), \
        "Dynamic pipeline log does not use the required standard logging format"
    assert "add" in lower and (amount_word in lower or re.search(rf"\b{amount}\b", lower)), \
        "Log does not include the newly transcribed audio instruction"
    assert re.search(r"(?im)(?:processed[^\n]{0,40}\b[34]\b|\b[34]\b[^\n]{0,40}records?[^\n]{0,20}processed)", content), \
        "Log does not state the number of records processed"
    assert re.search(rf"(?im)^.*\bERROR\b.*(?:{bad_id}|parsing|parse|invalid|unsupported).*$", content), \
        "Log does not record the malformed expression parsing error"
finally:
    if proc.poll() is None:
        # Leave the successfully relaunched submitted server running, as requested.
        pass
    server_output.close()
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
