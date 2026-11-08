#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import socket
import time
import uuid
import pytest


def test_proxy_executable_exists():
    executable_path = "/home/user/workspace/proxy"
    assert os.path.isfile(executable_path), f"The proxy executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"The file {executable_path} is not executable."


def test_logs_directory_permissions():
    logs_dir = "/home/user/logs"
    assert os.path.isdir(logs_dir), f"The directory {logs_dir} does not exist."

    st = os.stat(logs_dir)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o700, f"Permissions for {logs_dir} are incorrect. Expected 0700, got {oct(permissions)}."


def test_cron_job_configured():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab or no crontab configured for the user.")

    expected_cron = "* * * * * /home/user/workspace/monitor.sh"
    normalized_crontab = [" ".join(line.split()) for line in crontab_output.splitlines()]
    assert expected_cron in normalized_crontab, "The expected cron job for monitor.sh is not configured correctly."


def test_proxy_functionality():
    payload = f"test_payload_{uuid.uuid4().hex}"
    payload_bytes = payload.encode("utf-8")

    receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiver.settimeout(3.0)
    try:
        receiver.bind(("127.0.0.1", 9090))
    except Exception as e:
        receiver.close()
        pytest.fail(f"Failed to start the backend receiver on 127.0.0.1:9090: {e}")

    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sender.sendto(payload_bytes, ("127.0.0.1", 8080))
    except Exception as e:
        pytest.fail(f"Failed to send UDP packet to 127.0.0.1:8080: {e}")
    finally:
        sender.close()

    try:
        forwarded_data, _ = receiver.recvfrom(65535)
    except socket.timeout:
        pytest.fail("The backend receiver did not receive a forwarded packet on 127.0.0.1:9090.")
    except Exception as e:
        pytest.fail(f"Failed while receiving the forwarded UDP packet: {e}")
    finally:
        receiver.close()

    assert forwarded_data == payload_bytes, (
        f"The packet received on port 9090 did not match the packet sent to port 8080. "
        f"Expected {payload_bytes!r}, got {forwarded_data!r}."
    )

    time.sleep(1.0)

    log_file = "/home/user/logs/proxy.log"
    assert os.path.isfile(log_file), f"The log file {log_file} does not exist."

    with open(log_file, "r") as f:
        log_content = f.read()

    expected_log_entry = f"FORWARDED: {payload}"
    assert expected_log_entry in log_content, f"The expected log entry '{expected_log_entry}' was not found in {log_file}. The proxy might not be running, listening on the correct port, or logging correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
