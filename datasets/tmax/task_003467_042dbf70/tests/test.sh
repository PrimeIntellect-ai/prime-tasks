#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import base64
import re
import difflib
import stat
import secrets
import subprocess
import pytest


def test_authorized_keys_permissions_and_content():
    target_file = "/home/user/authorized_keys"
    traffic_log = "/app/traffic.log"

    assert os.path.exists(target_file), f"Output file {target_file} does not exist."

    # Check permissions (must be 0600)
    file_stat = os.stat(target_file)
    perms = oct(file_stat.st_mode)[-3:]
    assert perms == "600", f"File permissions for {target_file} must be 600, got {perms}."

    # Derive the expected key from the traffic log
    assert os.path.exists(traffic_log), f"Missing {traffic_log} to derive the expected key."

    expected_key = None
    with open(traffic_log, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("PAYLOAD:"):
                b64_payload = line.split("PAYLOAD:")[1]
                try:
                    decoded = base64.b64decode(b64_payload).decode('utf-8', errors='ignore')
                    # The audio intercept says the key ends with XYZ7NQ==
                    if "XYZ7NQ==" in decoded:
                        # Redact the internal 10.x.x.x IP address
                        expected_key = re.sub(r'10\.\d+\.\d+\.\d+', '[REDACTED]', decoded).strip()
                        break
                except Exception:
                    continue

    assert expected_key is not None, "Could not derive the expected key from traffic.log."

    # Read the agent's output
    with open(target_file, "r") as f:
        content = f.read().strip()

    # Calculate similarity ratio (using difflib.SequenceMatcher as a standard library equivalent to Levenshtein ratio)
    ratio = difflib.SequenceMatcher(None, content, expected_key).ratio()

    assert ratio >= 0.95, (
        f"Metric: {ratio} < 0.95\n"
        f"The authorized_keys content does not match the expected output closely enough.\n"
        f"Expected (redacted): {expected_key}\n"
        f"Got: {content}"
    )


def test_cpp_implementation_compiles_and_processes_fresh_payloads():
    source = "/home/user/process_keys.cpp"
    executable = "/home/user/process_keys"
    traffic_log = "/app/traffic.log"
    target_file = "/home/user/authorized_keys"

    assert os.path.isfile(source), f"Required C++ source file {source} is missing."

    compile_result = subprocess.run(
        ["g++", "-O2", "-std=c++17", source, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "process_keys.cpp did not compile with the required command:\n"
        + compile_result.stderr
    )
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), (
        "Compilation did not produce an executable /home/user/process_keys."
    )

    original_traffic = open(traffic_log, "rb").read()
    original_output = open(target_file, "rb").read() if os.path.exists(target_file) else None
    original_mode = stat.S_IMODE(os.stat(target_file).st_mode) if os.path.exists(target_file) else None

    nonce = secrets.token_hex(12)
    decoy = f"ssh-rsa AAAAB3NzaFreshDecoy{nonce}QWE32== decoy@localhost"
    selected = f"ssh-rsa AAAAB3NzaFreshSelected{nonce}XYZ7NQ== analyst@10.23.45.67"
    expected = re.sub(r'10\.\d+\.\d+\.\d+', '[REDACTED]', selected).strip()
    fresh_log = "\n".join(
        "PAYLOAD:" + base64.b64encode(item.encode()).decode()
        for item in (decoy, selected)
    ) + "\n"

    try:
        with open(traffic_log, "w") as f:
            f.write(fresh_log)
        if os.path.exists(target_file):
            os.unlink(target_file)

        run_result = subprocess.run(
            [executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert run_result.returncode == 0, (
            "Compiled process_keys program exited unsuccessfully:\n" + run_result.stderr
        )

        if os.path.isfile(target_file):
            with open(target_file, "r") as f:
                produced = f.read().strip()
        else:
            # The instruction permits a subsequent shell command to write the
            # program's output, so stdout is also an acceptable program result.
            produced = run_result.stdout.strip()

        ratio = difflib.SequenceMatcher(None, produced, expected).ratio()
        assert ratio >= 0.95, (
            f"The compiled C++ program did not process fresh payloads correctly.\n"
            f"Expected (redacted): {expected}\n"
            f"Got: {produced}\n"
            f"Metric: {ratio}"
        )
        assert not re.search(r'10\.\d+\.\d+\.\d+', produced), (
            "The compiled C++ program left a sensitive internal IP unredacted."
        )
    finally:
        with open(traffic_log, "wb") as f:
            f.write(original_traffic)
        if original_output is None:
            if os.path.exists(target_file):
                os.unlink(target_file)
        else:
            with open(target_file, "wb") as f:
                f.write(original_output)
            os.chmod(target_file, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
