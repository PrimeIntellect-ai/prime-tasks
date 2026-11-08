#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_directories_and_symlink():
    """Test that the required directories and symlink are created correctly."""
    assert os.path.isdir("/home/user/storage/net_logs"), "Directory /home/user/storage/net_logs does not exist."
    assert os.path.isdir("/home/user/mail"), "Directory /home/user/mail does not exist."

    assert os.path.islink("/home/user/logs"), "/home/user/logs is not a symlink."
    target = os.readlink("/home/user/logs")
    assert target == "/home/user/storage/net_logs", f"Symlink /home/user/logs points to {target} instead of /home/user/storage/net_logs."


def test_my_fstab():
    """Test that my_fstab consists of exactly the required mount entry."""
    fstab_path = "/home/user/my_fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        content = f.read()

    expected_line = "//10.0.0.50/netdata /home/user/storage/net_logs cifs defaults,ro 0 0"
    assert expected_line in content, f"The expected line was not found in {fstab_path}."
    assert content in (expected_line, expected_line + "\n"), f"{fstab_path} must contain exactly the required line."


def test_script_executable():
    """Test that the net_alert.sh script exists and is executable."""
    script_path = "/home/user/net_alert.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_script_behavior():
    """Retain the original behavioral and rotation checks."""
    script_path = "/home/user/net_alert.sh"
    log_path = "/home/user/logs/sensor.log"
    alerts_path = "/home/user/mail/alerts.txt"

    if os.path.exists(alerts_path):
        os.remove(alerts_path)

    mock_log_content = """2023-10-12T10:00:00Z IP=192.168.1.10 STATE=UP PING=12
2023-10-12T10:01:00Z IP=192.168.1.15 STATE=DOWN PING=-1
2023-10-12T10:02:00Z IP=10.0.0.2 STATE=UP PING=5
2023-10-12T10:03:00Z IP=192.168.1.99 STATE=DOWN PING=-1
"""
    with open(log_path, "w") as f:
        f.write(mock_log_content)

    result = subprocess.run([script_path, log_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script exited with non-zero return code: {result.returncode}\nStderr: {result.stderr}"

    assert os.path.isfile(alerts_path), f"Alerts file {alerts_path} was not created."
    with open(alerts_path, "r") as f:
        alerts_content = f.read().strip()

    expected_alerts = "ALERT: Host 192.168.1.15 is DOWN\nALERT: Host 192.168.1.99 is DOWN"
    assert alerts_content == expected_alerts, f"Alerts content is incorrect.\nExpected:\n{expected_alerts}\nGot:\n{alerts_content}"

    bak_path = f"{log_path}.bak"
    assert os.path.isfile(bak_path), f"Backup file {bak_path} was not created."
    with open(bak_path, "r") as f:
        bak_content = f.read()
    assert bak_content == mock_log_content, "Backup file does not contain the original log data."

    assert os.path.isfile(log_path), "New empty log file was not created."
    assert os.path.getsize(log_path) == 0, f"New log file {log_path} is not empty."


def _unique_ips(count):
    result = []
    seen = set()
    while len(result) < count:
        ip = f"{secrets.randbelow(223) + 1}.{secrets.randbelow(256)}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}"
        if ip not in seen:
            seen.add(ip)
            result.append(ip)
    return result


def test_script_on_runtime_generated_logs_and_argument_paths():
    """Exercise parsing on undisclosed values and non-fixed input paths."""
    script_path = "/home/user/net_alert.sh"
    alerts_path = "/home/user/mail/alerts.txt"
    marker = f"existing-alert-{secrets.token_hex(12)}"
    with open(alerts_path, "w") as f:
        f.write(marker + "\n")

    expected_lines = [marker]

    for case_number in range(2):
        token = secrets.token_hex(10)
        log_path = f"/home/user/logs/runtime-{token}.log"
        bak_path = log_path + ".bak"
        ips = _unique_ips(7)
        states = ["UP", "DOWN", "UP", "DOWN", "DOWN", "UP", "DOWN"]
        lines = []

        for index, (ip, state) in enumerate(zip(ips, states)):
            timestamp = f"20{secrets.randbelow(20) + 25:02d}-{secrets.randbelow(12) + 1:02d}-{secrets.randbelow(28) + 1:02d}T{secrets.randbelow(24):02d}:{secrets.randbelow(60):02d}:{secrets.randbelow(60):02d}Z"
            ping = -1 if state == "DOWN" else secrets.randbelow(900) + 1
            lines.append(f"{timestamp} IP={ip} STATE={state} PING={ping}\n")
            if state == "DOWN":
                expected_lines.append(f"ALERT: Host {ip} is DOWN")

        original_content = "".join(lines)
        with open(log_path, "w") as f:
            f.write(original_content)
        with open(bak_path, "w") as f:
            f.write(f"stale-backup-{case_number}-{token}")

        result = subprocess.run([script_path, log_path], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed for generated input: {result.stderr}"

        assert os.path.isfile(bak_path), f"Backup file {bak_path} was not created."
        with open(bak_path, "r") as f:
            assert f.read() == original_content, "Backup was not overwritten with the generated input."
        assert os.path.isfile(log_path), f"Original path {log_path} was not recreated."
        assert os.path.getsize(log_path) == 0, f"Recreated log {log_path} is not empty."

        with open(alerts_path, "r") as f:
            actual_lines = f.read().splitlines()
        assert actual_lines == expected_lines, f"Alerts were not correctly appended for generated case {case_number}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
