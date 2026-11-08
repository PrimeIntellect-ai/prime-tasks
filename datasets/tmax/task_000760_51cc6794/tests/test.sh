#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os


def recover_expected_ip():
    anomalies = []

    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue

        try:
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

        if b'traffic_sim.sh' not in cmdline:
            continue

        fd_dir = f'/proc/{pid}/fd'
        try:
            fds = os.listdir(fd_dir)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

        for fd in fds:
            fd_path = f'{fd_dir}/{fd}'
            try:
                target = os.readlink(fd_path)
            except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
                continue

            if target != '/home/user/service.log (deleted)':
                continue

            try:
                with open(fd_path, 'r') as f:
                    log_data = f.read()
            except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
                continue

            for line in log_data.splitlines():
                try:
                    entry = json.loads(line)
                except (json.JSONDecodeError, TypeError):
                    continue
                if entry.get('status') == 500 and entry.get('latency', 0) > 8000:
                    anomalies.append(entry.get('ip'))

    assert len(anomalies) == 1, f'Expected one anomalous entry in the deleted log, found {len(anomalies)}.'
    return anomalies[0]


def test_culprit_ip_file_exists():
    file_path = '/home/user/culprit_ip.txt'
    assert os.path.isfile(file_path), f'The file {file_path} does not exist.'


def test_culprit_ip_content():
    file_path = '/home/user/culprit_ip.txt'
    assert os.path.isfile(file_path), f'The file {file_path} does not exist.'

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_ip = recover_expected_ip()
    assert content == expected_ip, f"Expected IP '{expected_ip}', but found '{content}' in {file_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
