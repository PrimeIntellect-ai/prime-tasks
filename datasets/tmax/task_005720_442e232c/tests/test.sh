#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import pytest

def test_script_exists_and_executable():
    script_path = "/home/user/generate_configs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_generated_files_content():
    requests_path = "/home/user/requests.txt"
    assert os.path.isfile(requests_path), f"Input file {requests_path} is missing."

    expected_errors = []
    expected_fstab = []
    expected_iptables = []

    with open(requests_path, "r") as f:
        for line in f:
            line_stripped = line.strip('\n')
            if not line_stripped:
                continue

            parts = line_stripped.split(',')
            if len(parts) == 3:
                username, port, path = parts
                expected_fstab.append(f"/data/common_share {path} none bind,ro 0 0")
                expected_iptables.append(f"iptables -t nat -A PREROUTING -p tcp --dport {port} -j DNAT --to-destination 10.0.0.5:22")
            else:
                expected_errors.append(line_stripped)

    # Check error.log
    error_log_path = "/home/user/error.log"
    if expected_errors:
        assert os.path.isfile(error_log_path), f"Expected {error_log_path} to be created."
        with open(error_log_path, "r") as f:
            actual_errors = [line.strip('\n') for line in f if line.strip('\n')]
        assert actual_errors == expected_errors, f"Content of {error_log_path} is incorrect."
    else:
        if os.path.exists(error_log_path):
            assert os.path.getsize(error_log_path) == 0, f"{error_log_path} should be empty."

    # Check fstab_generated
    fstab_path = "/home/user/fstab_generated"
    if expected_fstab:
        assert os.path.isfile(fstab_path), f"Expected {fstab_path} to be created."
        with open(fstab_path, "r") as f:
            actual_fstab = [line.strip('\n') for line in f if line.strip('\n')]
        assert actual_fstab == expected_fstab, f"Content of {fstab_path} is incorrect."

    # Check port_forwards.rules
    iptables_path = "/home/user/port_forwards.rules"
    if expected_iptables:
        assert os.path.isfile(iptables_path), f"Expected {iptables_path} to be created."
        with open(iptables_path, "r") as f:
            actual_iptables = [line.strip('\n') for line in f if line.strip('\n')]
        assert actual_iptables == expected_iptables, f"Content of {iptables_path} is incorrect."

def test_script_executes_on_altered_input_and_clears_outputs():
    script_path = "/home/user/generate_configs.sh"
    requests_path = "/home/user/requests.txt"
    output_paths = [
        "/home/user/error.log",
        "/home/user/fstab_generated",
        "/home/user/port_forwards.rules",
    ]

    paths_to_restore = [requests_path] + output_paths
    snapshots = {}
    for path in paths_to_restore:
        snapshots[path] = open(path, "rb").read() if os.path.exists(path) else None

    token = secrets.token_hex(8)
    port1 = str(20000 + secrets.randbelow(10000))
    port2 = str(30000 + secrets.randbelow(10000))
    valid1 = f"dynamic_{token},{port1},/home/user/jails/dynamic_{token}/share"
    malformed1 = f"broken_{token},{port1}"
    valid2 = f"second_{token},{port2},/srv/isolation/{token}/share"
    malformed2 = f"too,many,fields,{token}"
    request_data = "\n".join([valid1, malformed1, "", valid2, malformed2]) + "\n"

    expected_errors = [malformed1, malformed2]
    expected_fstab = [
        f"/data/common_share /home/user/jails/dynamic_{token}/share none bind,ro 0 0",
        f"/data/common_share /srv/isolation/{token}/share none bind,ro 0 0",
    ]
    expected_iptables = [
        f"iptables -t nat -A PREROUTING -p tcp --dport {port1} -j DNAT --to-destination 10.0.0.5:22",
        f"iptables -t nat -A PREROUTING -p tcp --dport {port2} -j DNAT --to-destination 10.0.0.5:22",
    ]

    try:
        with open(requests_path, "w") as f:
            f.write(request_data)
        for path in output_paths:
            with open(path, "w") as f:
                f.write(f"STALE_CONTENT_{token}\n")

        result = subprocess.run(
            [script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Script exited with status {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )

        for path in output_paths:
            assert os.path.isfile(path), f"Expected {path} to be created by the script."

        with open("/home/user/error.log", "r") as f:
            actual_errors = [line.strip('\n') for line in f if line.strip('\n')]
        with open("/home/user/fstab_generated", "r") as f:
            actual_fstab = [line.strip('\n') for line in f if line.strip('\n')]
        with open("/home/user/port_forwards.rules", "r") as f:
            actual_iptables = [line.strip('\n') for line in f if line.strip('\n')]

        assert actual_errors == expected_errors, "error.log was not regenerated correctly."
        assert actual_fstab == expected_fstab, "fstab_generated was not regenerated correctly."
        assert actual_iptables == expected_iptables, "port_forwards.rules was not regenerated correctly."
    finally:
        for path, content in snapshots.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
