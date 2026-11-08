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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import time
import secrets
import requests
import pytest
import subprocess


def test_files_exist_and_permissions():
    assert os.path.isfile("/home/user/deploy_gateway.go"), "deploy_gateway.go is missing"

    rollout_path = "/home/user/rollout.sh"
    assert os.path.isfile(rollout_path), "rollout.sh is missing"

    st = os.stat(rollout_path)
    assert bool(st.st_mode & stat.S_IXUSR), "rollout.sh is not executable"


def test_http_endpoint_unauthorized():
    url = "http://127.0.0.1:8080/deploy"

    try:
        response = requests.post(url, timeout=2)
        assert response.status_code == 401, f"Expected 401 for missing header, got {response.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go application: {e}")

    try:
        response = requests.post(url, headers={"X-Voice-Auth": "123456"}, timeout=2)
        assert response.status_code == 401, f"Expected 401 for wrong header, got {response.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go application: {e}")


def test_http_endpoint_authorized_and_rollout():
    url = "http://127.0.0.1:8080/deploy"
    log_file = "/home/user/deploy_log.txt"
    if os.path.exists(log_file):
        os.remove(log_file)

    try:
        response = requests.post(url, headers={"X-Voice-Auth": "839201"}, timeout=5)
        assert response.status_code == 200, f"Expected 200 OK for correct header, got {response.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go application: {e}")

    time.sleep(1)

    assert os.path.isfile(log_file), "deploy_log.txt was not created after successful deployment"

    with open(log_file, "r") as f:
        content = f.read().strip().split('\n')

    expected_lines = [
        "DEPLOYED TO: 192.168.1.10",
        "DEPLOYED TO: 192.168.1.11",
        "DEPLOYED TO: 10.0.0.5"
    ]

    assert len(content) == 3, f"Expected 3 lines in deploy_log.txt, got {len(content)}"
    for expected, actual in zip(expected_lines, content):
        assert expected == actual, f"Expected log line '{expected}', but got '{actual}'"


def test_rollout_script_error_handling(tmp_path):
    servers_path = "/app/servers.txt"
    backup_path = "/app/servers.txt.bak"

    if os.path.exists(servers_path):
        os.rename(servers_path, backup_path)

    log_file = "/home/user/deploy_log.txt"
    if os.path.exists(log_file):
        os.remove(log_file)

    try:
        result = subprocess.run(["/home/user/rollout.sh"], capture_output=True)
        assert result.returncode == 1, f"Expected rollout.sh to exit with code 1 when servers.txt is missing, got {result.returncode}"

        assert os.path.isfile(log_file), "deploy_log.txt was not created during error handling"
        with open(log_file, "r") as f:
            content = f.read().strip()

        assert "ERROR: servers.txt missing" in content, f"Expected error message in log, got: {content}"
    finally:
        if os.path.exists(backup_path):
            os.rename(backup_path, servers_path)


def test_rollout_parses_arbitrary_server_list():
    servers_path = "/app/servers.txt"
    log_file = "/home/user/deploy_log.txt"
    original = open(servers_path, "rb").read()

    octets = [secrets.randbelow(200) + 20 for _ in range(6)]
    targets = [
        f"172.20.{octets[0]}.{octets[1]}",
        f"10.{octets[2]}.{octets[3]}.{octets[4]}",
        f"192.0.2.{octets[5]}",
    ]
    fixture = (
        "# dynamically generated primary group\n"
        + targets[0] + "\n"
        + "\n"
        + "# ignored comment\n"
        + targets[1] + "\n"
        + "\n"
        + targets[2] + "\n"
    )

    try:
        with open(servers_path, "w") as f:
            f.write(fixture)
        if os.path.exists(log_file):
            os.remove(log_file)

        result = subprocess.run(["/home/user/rollout.sh"], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"rollout.sh failed for a valid dynamic server list: {result.stderr}"
        assert os.path.isfile(log_file), "rollout.sh did not create deploy_log.txt"

        with open(log_file, "r") as f:
            actual = f.read().splitlines()
        expected = [f"DEPLOYED TO: {target}" for target in targets]
        assert actual == expected, f"Expected dynamically derived deployment lines {expected}, got {actual}"
    finally:
        with open(servers_path, "wb") as f:
            f.write(original)


def test_gateway_actually_executes_rollout_script():
    rollout_path = "/home/user/rollout.sh"
    marker = f"/tmp/rollout-invoked-{secrets.token_hex(12)}"
    token = secrets.token_hex(16)
    with open(rollout_path, "rb") as f:
        original_script = f.read()
    original_mode = stat.S_IMODE(os.stat(rollout_path).st_mode)

    probe = f"#!/bin/bash\nprintf '%s' '{token}' > '{marker}'\nexit 0\n".encode()
    try:
        with open(rollout_path, "wb") as f:
            f.write(probe)
        os.chmod(rollout_path, original_mode | stat.S_IXUSR)

        response = requests.post(
            "http://127.0.0.1:8080/deploy",
            headers={"X-Voice-Auth": "839201"},
            timeout=5,
        )
        assert response.status_code == 200, f"Expected 200 from gateway probe, got {response.status_code}"

        deadline = time.time() + 2
        while time.time() < deadline and not os.path.exists(marker):
            time.sleep(0.05)
        assert os.path.isfile(marker), "Authorized gateway request did not execute /home/user/rollout.sh"
        with open(marker, "r") as f:
            assert f.read() == token, "Gateway invocation marker had unexpected contents"
    finally:
        with open(rollout_path, "wb") as f:
            f.write(original_script)
        os.chmod(rollout_path, original_mode)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
