#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import stat
import string
import subprocess
import pytest

SERVICE = "netdiag-replica.service"
UNIT_PATH = "/home/user/.config/systemd/user/netdiag-replica.service"
DEPLOY_PATH = "/home/user/deploy_service.sh"
LOG_PATH = "/home/user/netdiag.log"


def assert_service_state():
    enabled_proc = subprocess.run(
        ["systemctl", "--user", "is-enabled", SERVICE],
        capture_output=True, text=True
    )
    assert enabled_proc.returncode == 0, (
        f"Service is not enabled. systemctl output: {enabled_proc.stdout.strip()}"
    )
    assert "enabled" in enabled_proc.stdout.strip(), "Service is not enabled"

    active_proc = subprocess.run(
        ["systemctl", "--user", "is-active", SERVICE],
        capture_output=True, text=True
    )
    assert active_proc.returncode == 0, (
        f"Service is not active. systemctl output: {active_proc.stdout.strip()}"
    )
    assert "active" in active_proc.stdout.strip(), "Service is not active"


def read_service_directives(path):
    section = None
    directives = {}
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1].strip()
                continue
            if section == "Service" and "=" in line:
                key, value = line.split("=", 1)
                directives.setdefault(key.strip(), []).append(value.strip())
    return directives


@pytest.fixture(scope="session", autouse=True)
def verify_deployment_script():
    assert os.path.exists(DEPLOY_PATH), f"Deployment script missing at {DEPLOY_PATH}"
    assert stat.S_ISREG(os.lstat(DEPLOY_PATH).st_mode), "Deployment script is not a regular file"

    syntax_proc = subprocess.run(
        ["bash", "-n", DEPLOY_PATH], capture_output=True, text=True
    )
    assert syntax_proc.returncode == 0, f"Deployment script is not valid bash: {syntax_proc.stderr}"

    # Remove prior deployment state so the submitted script must create, enable,
    # and start the requested service itself.
    subprocess.run(
        ["systemctl", "--user", "disable", "--now", SERVICE],
        capture_output=True, text=True
    )
    if os.path.lexists(UNIT_PATH):
        os.remove(UNIT_PATH)
    if os.path.lexists(LOG_PATH):
        os.remove(LOG_PATH)
    subprocess.run(
        ["systemctl", "--user", "daemon-reload"], capture_output=True, text=True
    )

    first = subprocess.run(
        ["bash", DEPLOY_PATH], capture_output=True, text=True, timeout=30
    )
    assert first.returncode == 0, (
        f"First deployment failed. stdout: {first.stdout}\nstderr: {first.stderr}"
    )
    assert os.path.exists(UNIT_PATH), f"Service file was not created at {UNIT_PATH}"
    assert stat.S_ISREG(os.lstat(UNIT_PATH).st_mode), "Service file is not a regular file"
    assert_service_state()
    with open(UNIT_PATH, "rb") as f:
        first_unit = f.read()

    second = subprocess.run(
        ["bash", DEPLOY_PATH], capture_output=True, text=True, timeout=30
    )
    assert second.returncode == 0, (
        f"Second deployment failed; script is not idempotent. "
        f"stdout: {second.stdout}\nstderr: {second.stderr}"
    )
    assert_service_state()
    with open(UNIT_PATH, "rb") as f:
        second_unit = f.read()
    assert second_unit == first_unit, "Repeated deployment changed or duplicated the service configuration"

    directives = read_service_directives(UNIT_PATH)
    exec_values = [v for v in directives.get("ExecStart", []) if v]
    assert len(exec_values) == 1, "Service must contain exactly one non-empty ExecStart directive"
    try:
        exec_argv = shlex.split(exec_values[0])
    except ValueError as exc:
        pytest.fail(f"Invalid ExecStart quoting: {exc}")
    assert exec_argv == [
        "/usr/bin/python3",
        "/home/user/netdiag_replica.py",
        "DEFAULT_PAYLOAD",
    ], f"Incorrect ExecStart: {exec_values[0]}"

    output_values = [v for v in directives.get("StandardOutput", []) if v]
    assert len(output_values) == 1, "Service must contain exactly one StandardOutput directive"
    assert output_values[0] in {
        "file:/home/user/netdiag.log",
        "append:/home/user/netdiag.log",
        "truncate:/home/user/netdiag.log",
    }, f"StandardOutput does not target /home/user/netdiag.log: {output_values[0]}"


def test_fuzz_equivalence():
    oracle_path = "/app/netdiag_obfuscated"
    agent_script = "/home/user/netdiag_replica.py"

    assert os.path.exists(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)
    chars = string.ascii_letters + string.digits + ".:-_"

    for _ in range(1000):
        length = random.randint(1, 256)
        payload = "".join(random.choice(chars) for _ in range(length))

        oracle_proc = subprocess.run([oracle_path, payload], capture_output=True, text=True)
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(["python3", agent_script, payload], capture_output=True, text=True)
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on input '{payload}'\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )


def test_systemd_service_state():
    # Check if enabled
    enabled_proc = subprocess.run(
        ["systemctl", "--user", "is-enabled", "netdiag-replica.service"],
        capture_output=True, text=True
    )
    assert enabled_proc.returncode == 0, f"Service is not enabled. systemctl output: {enabled_proc.stdout.strip()}"
    assert "enabled" in enabled_proc.stdout.strip(), "Service is not enabled"

    # Check if active
    active_proc = subprocess.run(
        ["systemctl", "--user", "is-active", "netdiag-replica.service"],
        capture_output=True, text=True
    )
    assert active_proc.returncode == 0, f"Service is not active. systemctl output: {active_proc.stdout.strip()}"
    assert "active" in active_proc.stdout.strip(), "Service is not active"


def test_log_file_content():
    log_path = "/home/user/netdiag.log"
    assert os.path.exists(log_path), f"Log file does not exist at {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()

    oracle_proc = subprocess.run(
        ["/app/netdiag_obfuscated", "DEFAULT_PAYLOAD"],
        capture_output=True, text=True
    )
    expected_out = oracle_proc.stdout.strip()

    assert content == expected_out, f"Log content mismatch. Expected: {expected_out}, Got: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
