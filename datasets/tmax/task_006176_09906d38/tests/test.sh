#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import gzip
import os
import secrets
import shutil
import subprocess
import tempfile

OUTPUT = "/home/user/critical_logs.gz"
LOG_ROOT = "/home/user/app_logs"

# Preserve the original verifier's assertions.
assert os.path.exists(OUTPUT), f"Output file {OUTPUT} does not exist."
assert os.path.isfile(OUTPUT), f"Output path {OUTPUT} is not a file."

expected_original = [
    "3|2023-10-01T10:02:00|FATAL|Kernel panic\n",
    "5|2023-10-01T10:05:00|ERROR|Disk full\n",
    "7|2023-10-01T10:07:00|ERROR|Network down\n",
    "8|2023-10-01T10:08:00|FATAL|OOM\n",
]
try:
    with gzip.open(OUTPUT, "rt") as f:
        actual_original = f.readlines()
except Exception as exc:
    raise AssertionError(f"Failed to read {OUTPUT} as a gzip text file: {exc}")
assert actual_original == expected_original, (
    f"The contents of {OUTPUT} do not match the expected output. "
    f"Expected {len(expected_original)} specific lines, but got "
    f"{len(actual_original)} lines. Actual content: {actual_original}"
)

# Add unpredictable nested inputs after the agent has finished, so a hardcoded
# output cannot satisfy the behavioral check.
token = secrets.token_hex(8)
base = secrets.randbelow(700000000) + 100000000
nested = os.path.join(LOG_ROOT, f"verify_{token}", "one", "two", "three")
os.makedirs(nested, exist_ok=True)

with open(os.path.join(nested, f"plain_{token}.wal"), "w") as f:
    f.write(f"{base + 100}|2042-01-01T00:00:00|ERROR|plain critical {token}\n")
    f.write(f"{base + 3}|2042-01-01T00:00:01|INFO|ignore {token}\n")
    f.write(f"{base + 11}|2042-01-01T00:00:02|FATAL|message|with|pipes {token}\n")

with gzip.open(os.path.join(LOG_ROOT, f"verify_{token}", f"compressed_{token}.wal.gz"), "wt") as f:
    f.write(f"-{base}|2042-01-02T00:00:00|FATAL|negative sequence {token}\n")
    f.write(f"{base + 2}|2042-01-02T00:00:01|ERROR|compressed critical {token}\n")
    f.write(f"{base + 4}|2042-01-02T00:00:02|error|wrong case {token}\n")

# This valid-looking log must be ignored because its suffix is not .wal/.wal.gz.
with open(os.path.join(nested, f"decoy_{token}.wal.gz.bak"), "w") as f:
    f.write(f"{base + 1}|2042-01-03T00:00:00|ERROR|extension decoy {token}\n")

def derive_expected():
    entries = []
    for root, _, files in os.walk(LOG_ROOT):
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".wal.gz"):
                opener = gzip.open
            elif name.endswith(".wal"):
                opener = open
            else:
                continue
            with opener(path, "rt") as f:
                for line in f:
                    parts = line.rstrip("\n").split("|", 3)
                    assert len(parts) == 4, f"Invalid test log line in {path}: {line!r}"
                    seq = int(parts[0])
                    if parts[2] in ("ERROR", "FATAL"):
                        entries.append((seq, line))
    entries.sort(key=lambda item: item[0])
    return [line for _, line in entries]

expected_dynamic = derive_expected()

# A Python script is an explicit required artifact. Locate regular .py files
# created under the user's home, including a script placed inside app_logs.
candidates = []
for root, dirs, files in os.walk("/home/user", followlinks=False):
    for name in files:
        if not name.endswith(".py"):
            continue
        path = os.path.join(root, name)
        if os.path.isfile(path) and not os.path.islink(path):
            candidates.append(path)
assert candidates, "No regular Python script was created under /home/user."

# Restore the same dynamic fixture before each candidate in case an unrelated
# Python file changes the inputs while being tried.
backup_parent = tempfile.mkdtemp(prefix="log-verifier-")
backup = os.path.join(backup_parent, "app_logs")
shutil.copytree(LOG_ROOT, backup)

passed = False
errors = []
for script in sorted(candidates):
    if os.path.exists(LOG_ROOT):
        shutil.rmtree(LOG_ROOT)
    shutil.copytree(backup, LOG_ROOT)
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    try:
        result = subprocess.run(
            ["python3", script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        if result.returncode != 0:
            errors.append(f"{script}: exited {result.returncode}")
            continue
        if not os.path.isfile(OUTPUT):
            errors.append(f"{script}: did not create {OUTPUT}")
            continue
        try:
            with gzip.open(OUTPUT, "rt") as f:
                actual_dynamic = f.readlines()
        except Exception as exc:
            errors.append(f"{script}: output is not readable gzip: {exc}")
            continue
        if actual_dynamic == expected_dynamic:
            passed = True
            break
        errors.append(f"{script}: produced incorrect dynamic output")
    except subprocess.TimeoutExpired:
        errors.append(f"{script}: timed out")

shutil.rmtree(backup_parent, ignore_errors=True)
assert passed, "No submitted Python script correctly processed the dynamic recursive fixture. " + "; ".join(errors)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
