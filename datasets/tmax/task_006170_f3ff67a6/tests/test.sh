#!/bin/bash
set -e
mkdir -p /logs/verifier

cp -a /home/user/bin/provisioner.sh /tmp/provisioner.sh.original
cp -a /home/user/config/limits.json /tmp/limits.json.original
restore_environment() {
    cp -a /tmp/provisioner.sh.original /home/user/bin/provisioner.sh
    chmod +x /home/user/bin/provisioner.sh
    cp -a /tmp/limits.json.original /home/user/config/limits.json
}
trap restore_environment EXIT

# Install an instrumented equivalent of the interactive provisioner so the
# verifier can validate every response and observe both lifecycle operations.
cat << 'PROVISIONER_EOF' > /home/user/bin/provisioner.sh
#!/usr/bin/env python3
import json
import os
import sys
import uuid

RUN_DIR = "/home/user/run/containers"
LOG_PATH = "/tmp/provisioner_events.jsonl"


def log_event(event):
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")


if len(sys.argv) > 1:
    if len(sys.argv) != 3 or sys.argv[1] != "--stop":
        print("Error: Invalid arguments")
        sys.exit(1)
    container_id = sys.argv[2]
    pid_file = os.path.join(RUN_DIR, container_id + ".pid")
    log_event({"event": "stop_attempt", "container_id": container_id})
    if not os.path.isfile(pid_file):
        print(f"Error: Container {container_id} not found.")
        sys.exit(1)
    os.remove(pid_file)
    log_event({"event": "stop", "container_id": container_id})
    print(f"Container {container_id} stopped.")
    sys.exit(0)

with open("/home/user/config/limits.json", "r", encoding="utf-8") as f:
    expected_storage = json.load(f)["max_storage_mb"]

print("Enter container name: ", end="", flush=True)
name = sys.stdin.readline().strip()
print("Enter storage limit (MB): ", end="", flush=True)
storage = sys.stdin.readline().strip()
print("Enable read-only rootfs? (y/n): ", end="", flush=True)
read_only = sys.stdin.readline().strip()

if name != "secure-con-01" or storage != str(expected_storage) or read_only != "y":
    log_event({
        "event": "invalid_answers",
        "name": name,
        "storage": storage,
        "read_only": read_only,
        "expected_storage": expected_storage,
    })
    print("Invalid provisioning answers.")
    sys.exit(2)

container_id = str(uuid.uuid4())
log_event({
    "event": "start",
    "container_id": container_id,
    "name": name,
    "storage": storage,
    "read_only": read_only,
})

if os.environ.get("VERIFIER_SKIP_PID") != "1":
    os.makedirs(RUN_DIR, exist_ok=True)
    with open(os.path.join(RUN_DIR, container_id + ".pid"), "w", encoding="utf-8") as f:
        f.write(str(os.getpid()) + "\n")

print(f"Initializing isolated environment for {name}...")
print(f"Applying quota: {storage}MB")
print(f"Successfully started container [ID: {container_id}]")
PROVISIONER_EOF
chmod +x /home/user/bin/provisioner.sh

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import re
import subprocess
import sys
import pytest

SCRIPT_PATH = "/home/user/harden_manager.py"
REPORT_PATH = "/home/user/hardening_report.json"
LIMITS_PATH = "/home/user/config/limits.json"
EVENTS_PATH = "/tmp/provisioner_events.jsonl"
RUN_DIR = "/home/user/run/containers"
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.I)


def write_limit(value):
    with open(LIMITS_PATH, "w", encoding="utf-8") as f:
        json.dump({"max_storage_mb": value, "cpu_shares": 512}, f)


def clean_runtime():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    if os.path.exists(EVENTS_PATH):
        os.remove(EVENTS_PATH)
    for path in glob.glob(os.path.join(RUN_DIR, "*.pid")):
        os.remove(path)


def read_events():
    if not os.path.exists(EVENTS_PATH):
        return []
    with open(EVENTS_PATH, "r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def run_manager(skip_pid=False):
    env = os.environ.copy()
    if skip_pid:
        env["VERIFIER_SKIP_PID"] = "1"
    else:
        env.pop("VERIFIER_SKIP_PID", None)
    return subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )


def assert_uses_pexpect():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    module_aliases = set()
    spawn_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    module_aliases.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            for alias in node.names:
                if alias.name == "spawn":
                    spawn_aliases.add(alias.asname or "spawn")

    used_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            if node.func.attr == "spawn" and isinstance(node.func.value, ast.Name) and node.func.value.id in module_aliases:
                used_spawn = True
        elif isinstance(node.func, ast.Name) and node.func.id in spawn_aliases:
            used_spawn = True

    assert module_aliases or spawn_aliases, "harden_manager.py must import pexpect."
    assert used_spawn, "harden_manager.py must use pexpect.spawn to automate the interactive provisioner."


def validate_successful_run(expected_storage):
    result = run_manager()
    assert result.returncode == 0, f"harden_manager.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(REPORT_PATH), "The executed manager did not create its report."

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    assert set(data) == {"container_name", "container_id", "storage_allocated", "status"}, "Report must contain exactly the required keys."
    assert data["container_name"] == "secure-con-01"
    assert type(data["storage_allocated"]) is int, "storage_allocated must be a JSON integer."
    assert data["storage_allocated"] == expected_storage
    assert data["status"] == "stopped"
    assert isinstance(data["container_id"], str) and UUID_RE.fullmatch(data["container_id"]), "container_id is not the provisioned UUID."

    events = read_events()
    starts = [event for event in events if event.get("event") == "start"]
    stops = [event for event in events if event.get("event") == "stop"]
    assert len(starts) == 1, f"Expected exactly one successful provisioning operation, got: {events}"
    assert len(stops) == 1, f"Expected exactly one successful stop operation, got: {events}"
    assert starts[0]["name"] == "secure-con-01"
    assert starts[0]["storage"] == str(expected_storage)
    assert starts[0]["read_only"] == "y"
    assert data["container_id"] == starts[0]["container_id"] == stops[0]["container_id"]
    assert not os.path.exists(os.path.join(RUN_DIR, data["container_id"] + ".pid"))


def test_00_manager_exists_uses_pexpect_and_executes_full_lifecycle():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert_uses_pexpect()

    # A manager that really checks PID creation must not claim success when the
    # provisioner deliberately omits the PID file.
    clean_runtime()
    write_limit(1379)
    failed = run_manager(skip_pid=True)
    successful_report = False
    if os.path.isfile(REPORT_PATH):
        try:
            with open(REPORT_PATH, "r", encoding="utf-8") as f:
                candidate = json.load(f)
            successful_report = candidate.get("status") == "stopped"
        except (json.JSONDecodeError, OSError):
            pass
    assert not successful_report, (
        "The manager reported success even though the provisioner did not create the required PID file. "
        f"stdout:\n{failed.stdout}\nstderr:\n{failed.stderr}"
    )

    # Use a non-default quota to prove the manager reads limits.json rather than
    # merely reporting the known setup value.
    clean_runtime()
    write_limit(1379)
    validate_successful_run(1379)

    # Leave the original expected final state in place for the original checks.
    clean_runtime()
    write_limit(1024)
    validate_successful_run(1024)


def test_hardening_report_exists_and_valid():
    report_path = "/home/user/hardening_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} was not created."

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {report_path} is not valid JSON.")

    assert "container_name" in data, "Missing 'container_name' in report."
    assert data["container_name"] == "secure-con-01", f"Expected container_name 'secure-con-01', got '{data['container_name']}'."

    assert "storage_allocated" in data, "Missing 'storage_allocated' in report."
    # We allow both int and string representation of int, though the prompt says integer value
    assert int(data["storage_allocated"]) == 1024, f"Expected storage_allocated to be 1024, got {data['storage_allocated']}."

    assert "status" in data, "Missing 'status' in report."
    assert data["status"] == "stopped", f"Expected status 'stopped', got '{data['status']}'."

    assert "container_id" in data, "Missing 'container_id' in report."
    container_id = data["container_id"]
    assert isinstance(container_id, str) and len(container_id) > 0, "Invalid 'container_id' in report."

    pid_file = f"/home/user/run/containers/{container_id}.pid"
    assert not os.path.exists(pid_file), f"Container PID file {pid_file} still exists. The container was not properly stopped."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
