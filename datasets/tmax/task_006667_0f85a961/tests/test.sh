#!/bin/bash
mkdir -p /logs/verifier
TEST_FILE="$(mktemp /tmp/test_final_state.XXXXXX.py)"
trap 'rm -f "$TEST_FILE"' EXIT

cat > "$TEST_FILE" <<'TEST_EOF'
import ast
import json
import os
import secrets
import stat
import subprocess

import pytest

SCRIPT = "/home/user/diagnose.py"
SUMMARY = "/home/user/summary.json"
IPTABLES = "/home/user/iptables.dump"
DISK_USAGE = "/home/user/disk_usage.txt"
CHECK_SERVICE = "/home/user/check_service.sh"


def assert_script_exists_and_uses_pexpect():
    assert os.path.exists(SCRIPT), f"The script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a regular file, not a symbolic link."

    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT} is not valid Python: {exc}")

    module_aliases = set()
    imported_spawn_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    module_aliases.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            for alias in node.names:
                if alias.name == "spawn":
                    imported_spawn_names.add(alias.asname or "spawn")

    assert module_aliases or imported_spawn_names, \
        "diagnose.py must import the pexpect module."

    uses_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in imported_spawn_names:
            uses_spawn = True
        elif (isinstance(node.func, ast.Attribute)
              and node.func.attr == "spawn"
              and isinstance(node.func.value, ast.Name)
              and node.func.value.id in module_aliases):
            uses_spawn = True
    assert uses_spawn, "diagnose.py must use pexpect.spawn to run the diagnostic tool."


def install_fixture(port, disk_pct, status):
    distractor_a = port + 1 if port < 65535 else port - 1
    distractor_b = port - 1 if port > 1 else port + 2

    iptables_text = f"""# Generated verifier fixture
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A PREROUTING -p tcp -m tcp --dport {distractor_a} -j DNAT --to-destination 127.0.0.1:9090
-A PREROUTING -p tcp -m tcp --dport {port} -j DNAT --to-destination 127.0.0.1:8080
-A PREROUTING -p tcp -m tcp --dport {distractor_b} -j DNAT --to-destination 127.0.0.1:8000
COMMIT
"""
    disk_text = f"""Filesystem      Size  Used Avail Use% Mounted on
udev            1.9G     0  1.9G   0% /dev
/dev/vda1        20G   10G   10G  50% /
/dev/vdb1       100G   50G   50G  {disk_pct}% /data
/dev/vdc1        50G   10G   40G  20% /backup
"""
    service_text = f"""#!/bin/bash
if [ ! -t 0 ]; then
    echo 'Error: diagnostic interaction requires a terminal'
    exit 9
fi
if [ -z "$1" ]; then
    echo "Usage: $0 <port>"
    exit 1
fi
if [ "$1" != "{port}" ]; then
    echo "Error: Service not configured on port $1"
    exit 1
fi
printf 'Enter Diagnostic PIN: '
read -r PIN
if [ "$PIN" = "7788" ]; then
    echo 'Authentication successful.'
    echo 'Status: {status}'
else
    echo 'Authentication failed.'
    echo 'Status: UNAUTHORIZED'
    exit 1
fi
"""

    with open(IPTABLES, "w", encoding="utf-8") as f:
        f.write(iptables_text)
    with open(DISK_USAGE, "w", encoding="utf-8") as f:
        f.write(disk_text)
    with open(CHECK_SERVICE, "w", encoding="utf-8") as f:
        f.write(service_text)
    os.chmod(IPTABLES, 0o644)
    os.chmod(DISK_USAGE, 0o644)
    os.chmod(CHECK_SERVICE, 0o755)


def run_diagnose():
    if os.path.lexists(SUMMARY):
        if os.path.isdir(SUMMARY) and not os.path.islink(SUMMARY):
            pytest.fail(f"{SUMMARY} is a directory and cannot be replaced by the script.")
        os.unlink(SUMMARY)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"diagnose.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_summary(port, disk_pct, status):
    assert os.path.exists(SUMMARY), \
        f"Expected output file {SUMMARY} does not exist. Did you run your script and generate it?"
    assert os.path.isfile(SUMMARY), f"{SUMMARY} is not a regular file."

    try:
        with open(SUMMARY, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Failed to parse {SUMMARY} as JSON: {exc}")

    assert isinstance(data, dict), f"JSON content in {SUMMARY} must be a dictionary/object."
    assert set(data) == {"external_port", "disk_usage_pct", "service_status"}, \
        "summary.json must contain exactly the requested keys."

    assert "external_port" in data, "Key 'external_port' is missing from summary.json."
    assert type(data["external_port"]) is int, "external_port must be an integer."
    assert data["external_port"] == port, \
        f"Expected external_port to be {port}, got {data['external_port']}."

    assert "disk_usage_pct" in data, "Key 'disk_usage_pct' is missing from summary.json."
    assert type(data["disk_usage_pct"]) is int, "disk_usage_pct must be an integer."
    assert data["disk_usage_pct"] == disk_pct, \
        f"Expected disk_usage_pct to be {disk_pct}, got {data['disk_usage_pct']}."

    assert "service_status" in data, "Key 'service_status' is missing from summary.json."
    assert type(data["service_status"]) is str, "service_status must be a string."
    assert data["service_status"] == status, \
        f"Expected service_status to be '{status}', got '{data['service_status']}'."


def test_diagnose_script_and_generated_summary():
    assert_script_exists_and_uses_pexpect()

    # Preserve the original verifier's assertions against the supplied scenario.
    install_fixture(5522, 92, "OK-DELAYED")
    run_diagnose()
    assert_summary(5522, 92, "OK-DELAYED")

    # Exercise parsing and interaction on values selected only at verification time.
    rng = secrets.SystemRandom()
    used_ports = {5522}
    for _ in range(2):
        port = rng.randint(12000, 60000)
        while port in used_ports:
            port = rng.randint(12000, 60000)
        used_ports.add(port)
        disk_pct = rng.randint(21, 98)
        status = "VERIFY-" + secrets.token_hex(6).upper()
        install_fixture(port, disk_pct, status)
        run_diagnose()
        assert_summary(port, disk_pct, status)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$TEST_FILE" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
