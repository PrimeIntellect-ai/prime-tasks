#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_provisioning.py
import glob
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

base = "/home/user/provisioning"
logs_dir = os.path.join(base, "logs")
script_path = os.path.join(base, "run_check.sh")
active_path = os.path.join(base, "active.conf")
prod_path = os.path.join(base, "configs/prod.conf")
log_path = os.path.join(logs_dir, "connectivity.log")

# Preserve the original final-state assertions.
old_files = glob.glob(os.path.join(logs_dir, "*.old"))
assert not old_files, f"Expected 0 .old files in {logs_dir}, found: {old_files}"
assert os.path.islink(active_path), f"Expected {active_path} to be a symbolic link"
assert os.path.realpath(active_path) == os.path.realpath(prod_path), (
    f"Symlink points to {os.path.realpath(active_path)}, expected {os.path.realpath(prod_path)}"
)
assert os.path.isfile(script_path), f"Script {script_path} does not exist"
assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"
with open(script_path, "rb") as f:
    first_line = f.readline()
assert first_line.startswith(b"#!") and b"bash" in first_line, "run_check.sh must be a bash script"
assert os.path.isfile(log_path), f"Log file {log_path} does not exist; the script was not run"

with open(prod_path, encoding="utf-8") as f:
    configured = [tuple(line.split()) for line in f if line.strip()]
assert all(len(endpoint) == 2 for endpoint in configured), "Invalid production configuration"
with open(log_path, encoding="utf-8") as f:
    final_lines = f.read().strip().splitlines()
assert len(final_lines) >= len(configured), "connectivity.log has too few result lines"
for line, (host, port) in zip(final_lines[-len(configured):], configured):
    assert re.fullmatch(rf"(?:SUCCESS|FAILURE): {re.escape(host)}:{re.escape(port)}", line), (
        f"Incorrectly formatted or ordered connectivity result: {line!r}"
    )

# Exercise the submitted script without relying on external network conditions.
original_config = open(prod_path, "rb").read()
backup_root = tempfile.mkdtemp(prefix="provisioning-verify-")
backup_logs = os.path.join(backup_root, "logs")
fakebin = os.path.join(backup_root, "bin")
os.mkdir(fakebin)
calls_path = os.path.join(backup_root, "nc-calls.jsonl")

fake_nc = os.path.join(fakebin, "nc")
with open(fake_nc, "w", encoding="utf-8") as f:
    f.write("""#!/usr/bin/python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['NC_CALLS'], 'a', encoding='utf-8') as out:
    out.write(json.dumps(args) + '\\n')
valid = '-z' in args
try:
    wi = args.index('-w')
    valid = valid and wi + 1 < len(args) and args[wi + 1] == '2'
except ValueError:
    valid = False
endpoint = args[-2:] if len(args) >= 2 else []
successes = json.loads(os.environ['NC_SUCCESSES'])
sys.exit(0 if valid and endpoint in successes else 1)
""")
os.chmod(fake_nc, 0o755)

env = os.environ.copy()
env["PATH"] = fakebin + os.pathsep + env.get("PATH", "")
env["NC_CALLS"] = calls_path

try:
    os.rename(logs_dir, backup_logs)

    # More than five files must stop the script before any connectivity attempt.
    os.mkdir(logs_dir)
    for i in range(6):
        open(os.path.join(logs_dir, f"guard-{i}.log"), "w").close()
    open(calls_path, "w").close()
    guard = subprocess.run(
        [script_path], env=env, text=True, capture_output=True, timeout=15
    )
    assert guard.returncode == 1, f"File-count guard returned {guard.returncode}, expected 1"
    assert "Storage quota exceeded" in guard.stdout.splitlines(), (
        f"Missing quota message in stdout: {guard.stdout!r}"
    )
    assert os.path.getsize(calls_path) == 0, "The script attempted connectivity after quota failure"

    # Use unpredictable endpoints and a controlled nc implementation to derive results.
    shutil.rmtree(logs_dir)
    os.mkdir(logs_dir)
    with open(log_path, "w", encoding="utf-8") as f:
        f.write("SENTINEL\n")

    token = uuid.uuid4().hex
    endpoints = [
        [f"alpha-{token}.invalid", "31001"],
        [f"beta-{token}.invalid", "31002"],
        [f"gamma-{token}.invalid", "31003"],
    ]
    successes = [endpoints[0], endpoints[2]]
    with open(prod_path, "w", encoding="utf-8") as f:
        f.write(f"{endpoints[0][0]} {endpoints[0][1]}\n\n")
        f.write(f"{endpoints[1][0]} {endpoints[1][1]}\n")
        f.write("   \n")
        f.write(f"{endpoints[2][0]} {endpoints[2][1]}\n")

    open(calls_path, "w").close()
    env["NC_SUCCESSES"] = json.dumps(successes)
    run = subprocess.run(
        [script_path], env=env, text=True, capture_output=True, timeout=20
    )
    assert run.returncode == 0, (
        f"run_check.sh failed under controlled connectivity test: stdout={run.stdout!r}, stderr={run.stderr!r}"
    )

    with open(calls_path, encoding="utf-8") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert len(calls) == len(endpoints), f"Expected {len(endpoints)} nc calls, found {len(calls)}"
    for args, endpoint in zip(calls, endpoints):
        assert "-z" in args, f"nc call is missing -z: {args}"
        assert "-w" in args and args.index("-w") + 1 < len(args) and args[args.index("-w") + 1] == "2", (
            f"nc call is missing '-w 2': {args}"
        )
        assert args[-2:] == endpoint, f"nc was called for the wrong endpoint: {args}"

    with open(log_path, encoding="utf-8") as f:
        observed = f.read().splitlines()
    expected = [
        "SENTINEL",
        f"SUCCESS: {endpoints[0][0]}:{endpoints[0][1]}",
        f"FAILURE: {endpoints[1][0]}:{endpoints[1][1]}",
        f"SUCCESS: {endpoints[2][0]}:{endpoints[2][1]}",
    ]
    assert observed == expected, f"Unexpected append output: {observed!r}"
finally:
    with open(prod_path, "wb") as f:
        f.write(original_config)
    if os.path.exists(logs_dir):
        shutil.rmtree(logs_dir)
    if os.path.exists(backup_logs):
        os.rename(backup_logs, logs_dir)
    shutil.rmtree(backup_root, ignore_errors=True)
PY_EOF

if python3 /tmp/verify_provisioning.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
