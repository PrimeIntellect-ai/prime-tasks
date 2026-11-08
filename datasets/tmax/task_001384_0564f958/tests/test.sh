#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import subprocess
import time
import urllib.request
import urllib.error
import pytest

SUPERVISOR_CONF = "/home/user/supervisor/supervisord.conf"
HEALTH_URL = "http://127.0.0.1:8080/api/health"


def test_success_file():
    success_file = "/home/user/success.txt"
    assert os.path.isfile(success_file), f"The file {success_file} was not created."

    with open(success_file, "r") as f:
        content = f.read().strip()

    assert content == '{"status": "ok"}', f"Expected success.txt to contain '{{\"status\": \"ok\"}}', but got '{content}'."


def test_nginx_proxy_works():
    url = HEALTH_URL
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            status_code = response.getcode()
            body = response.read().decode("utf-8").strip()

        assert status_code == 200, f"Expected HTTP 200 OK, got {status_code}"
        assert body == '{"status": "ok"}', f"Expected response body '{{\"status\": \"ok\"}}', got '{body}'"
    except urllib.error.HTTPError as e:
        pytest.fail(f"HTTP error occurred while accessing {url}: {e.code} {e.reason}")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to {url}: {e.reason}")
    except Exception as e:
        pytest.fail(f"An unexpected error occurred: {e}")


def test_supervisor_process_running():
    cmd = ["supervisorctl", "-c", SUPERVISOR_CONF, "status", "backend-api"]
    try:
        output = subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)
        assert "RUNNING" in output, f"Expected backend-api to be RUNNING, but got status output:\n{output}"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"supervisorctl command failed with exit code {e.returncode} and output:\n{e.output}")


def test_deploy_sh_updated():
    deploy_script = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_script), f"The file {deploy_script} is missing."

    with open(deploy_script, "r") as f:
        content = f.read()

    assert "supervisorctl" in content, "The deploy.sh script does not contain a 'supervisorctl' command."

    old_pid_output = subprocess.check_output(
        ["supervisorctl", "-c", SUPERVISOR_CONF, "pid", "backend-api"],
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()
    assert old_pid_output.isdigit() and int(old_pid_output) > 0, (
        f"Could not determine the running backend-api PID before deployment: {old_pid_output!r}"
    )
    old_pid = int(old_pid_output)

    try:
        result = subprocess.run(
            ["/bin/bash", "-x", deploy_script],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("deploy.sh did not finish within 20 seconds.")

    assert result.returncode == 0, (
        f"deploy.sh failed with exit code {result.returncode}. Output:\n{result.stdout}"
    )

    traced_restart = re.search(
        r"^\++\s+(?:\S*/)?supervisorctl(?:\s+\S+)*\s+restart\s+backend-api(?:\s|$)",
        result.stdout,
        flags=re.MULTILINE,
    )
    assert traced_restart, (
        "deploy.sh did not execute a supervisorctl restart command for backend-api. "
        f"Execution trace:\n{result.stdout}"
    )

    deadline = time.time() + 10
    last_status = ""
    new_pid = None
    while time.time() < deadline:
        status_result = subprocess.run(
            ["supervisorctl", "-c", SUPERVISOR_CONF, "status", "backend-api"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        last_status = status_result.stdout
        pid_result = subprocess.run(
            ["supervisorctl", "-c", SUPERVISOR_CONF, "pid", "backend-api"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        pid_text = pid_result.stdout.strip()
        if status_result.returncode == 0 and "RUNNING" in last_status and pid_text.isdigit():
            new_pid = int(pid_text)
            if new_pid > 0 and new_pid != old_pid:
                break
        time.sleep(0.25)

    assert new_pid is not None and new_pid > 0 and new_pid != old_pid, (
        "deploy.sh did not functionally restart backend-api with a new running PID. "
        f"Old PID: {old_pid}; last status: {last_status!r}; new PID: {new_pid!r}"
    )

    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=5) as response:
            body = response.read().decode("utf-8").strip()
            assert response.getcode() == 200
            assert body == '{"status": "ok"}'
    except Exception as e:
        pytest.fail(f"Health endpoint failed after deploy.sh restarted backend-api: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
