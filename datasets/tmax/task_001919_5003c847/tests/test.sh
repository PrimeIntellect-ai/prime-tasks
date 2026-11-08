#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import json
import random
import string
import subprocess
import importlib.util
import pytest


def test_vendored_package_fixed_and_installed():
    """Test that the vendored package bug is fixed and the package is installed."""
    connection_py_path = "/app/vendor/tunneled_smtp_client-0.9/tunneled_smtp_client/connection.py"

    assert os.path.isfile(connection_py_path), f"File {connection_py_path} is missing."

    with open(connection_py_path, 'r') as f:
        content = f.read()

    # The bug was "actual_ssh_port = 22"
    assert "actual_ssh_port = 22" not in content, "The bug 'actual_ssh_port = 22' is still present."
    # It should use self.ssh_port
    assert "self.ssh_port" in content, "The fix should use 'self.ssh_port'."

    # Exercise the vendored source directly with configured, non-default ports.
    spec = importlib.util.spec_from_file_location("vendored_connection", connection_py_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for port in (2207, 49157):
        connection = module.TunneledConnection("bastion.internal", ssh_port=port)
        assert connection.connect() == f"Connecting to bastion.internal on port {port}"

    # Check if package is installed in user environment
    result = subprocess.run([sys.executable, "-m", "pip", "show", "tunneled-smtp-client"], capture_output=True, text=True)
    assert result.returncode == 0, "Package tunneled_smtp_client is not installed."
    assert "Location:" in result.stdout

    # Confirm the installed import resolves to the vendored package and behaves correctly.
    port = random.SystemRandom().randint(30000, 60000)
    code = (
        "import os; "
        "import tunneled_smtp_client.connection as c; "
        "print(os.path.realpath(c.__file__)); "
        f"print(c.TunneledConnection('installed-bastion', ssh_port={port}).connect())"
    )
    imported = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
    assert imported.returncode == 0, f"Installed package cannot be imported: {imported.stderr}"
    lines = imported.stdout.splitlines()
    assert len(lines) >= 2
    assert os.path.realpath(lines[0]) == os.path.realpath(connection_py_path), (
        f"Installed package does not resolve to the vendored source: {lines[0]}"
    )
    assert lines[1] == f"Connecting to installed-bastion on port {port}"


def generate_random_service_name():
    length = random.randint(3, 15)
    chars = string.ascii_lowercase + string.digits + "-"
    return "".join(random.choice(chars) for _ in range(length))


def generate_random_json_input():
    num_services = random.randint(1, 20)
    data = []
    errors = ["timeout", "connection refused", "503 bad gateway", "internal server error"]
    for _ in range(num_services):
        status = random.choice(["up", "down"])
        if status == "up":
            data.append({
                "service": generate_random_service_name(),
                "status": "up",
                "latency_ms": random.randint(1, 5000),
                "error": None
            })
        else:
            data.append({
                "service": generate_random_service_name(),
                "status": "down",
                "latency_ms": -1,
                "error": random.choice(errors)
            })
    return json.dumps(data)


def test_format_alert_fuzz_equivalence():
    """Test that format_alert.py matches oracle_format_alert on random inputs."""
    oracle_path = "/app/oracle_format_alert"
    agent_script = "/home/user/format_alert.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.isfile(oracle_path), f"Oracle binary {oracle_path} is missing."

    random.seed(42)

    for i in range(100):
        json_input = generate_random_json_input()

        oracle_proc = subprocess.run([oracle_path, json_input], capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on input: {json_input}\nStderr: {oracle_proc.stderr}"

        agent_proc = subprocess.run([sys.executable, agent_script, json_input], capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent script failed on input: {json_input}\nStderr: {agent_proc.stderr}"

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on input {i}:\n"
            f"Input: {json_input}\n"
            f"Expected (Oracle):\n{oracle_proc.stdout}\n"
            f"Got (Agent):\n{agent_proc.stdout}"
        )


def test_cron_job_setup():
    """Test that the cron file exists and its job is correctly loaded into crontab."""
    cron_file = "/home/user/monitoring_cron"
    expected_cron = "*/5 * * * * /home/user/run_monitor.sh"

    assert os.path.isfile(cron_file), f"Cron configuration file {cron_file} is missing."
    with open(cron_file, "r") as f:
        file_lines = [line.strip() for line in f if line.strip() and not line.lstrip().startswith("#")]
    assert expected_cron in file_lines, f"Cron file does not contain the required entry. Got: {file_lines}"

    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab. Is it installed?"

    assert expected_cron in result.stdout, f"Crontab does not contain expected entry. Got:\n{result.stdout}"
    loaded_lines = [line.strip() for line in result.stdout.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert expected_cron in loaded_lines, "The required cron entry is not loaded as a complete, valid crontab line."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
