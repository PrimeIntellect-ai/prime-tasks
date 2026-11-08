#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/redact.sh"
EXPECTED_TOKEN = "TKN_7x9qL2vP"


def discover_live_process_token():
    tokens = set()
    matching_processes = 0

    for cmdline_path in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            with open(cmdline_path, "rb") as f:
                argv = [part.decode("utf-8", "replace") for part in f.read().split(b"\0") if part]
            if not any(os.path.basename(arg) == "simulate_traffic.sh" for arg in argv):
                continue

            stat_path = os.path.join(os.path.dirname(cmdline_path), "stat")
            with open(stat_path, "r") as f:
                stat = f.read()
            state = stat[stat.rfind(")") + 2:].split()[0]
            if state == "Z":
                continue

            matching_processes += 1
            for arg in argv:
                if arg.startswith("--token="):
                    tokens.add(arg[len("--token="):])
        except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
            continue

    assert matching_processes > 0, "No live simulate_traffic.sh process was found."
    assert len(tokens) == 1, "The live simulate_traffic.sh process must expose exactly one token value."
    return next(iter(tokens))


def test_redact_script_exists_and_executable():
    script_path = "/home/user/redact.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_simulate_traffic_process_is_still_running_with_leaked_token():
    assert discover_live_process_token() == EXPECTED_TOKEN


def test_traffic_redacted_log_content():
    log_path = "/home/user/logs/traffic_redacted.log"
    assert os.path.isfile(log_path), f"The output log file {log_path} does not exist."

    expected_content = """[2023-10-27 10:00:01] Connection received from [IP_REDACTED]
[2023-10-27 10:00:02] Auth attempt with token [REDACTED] - SUCCESS
[2023-10-27 10:00:05] Data packet sent to [IP_REDACTED], payload size 1024
[2023-10-27 10:01:00] Admin login from [IP_REDACTED] using [REDACTED]
[2023-10-27 10:01:15] Ping from [IP_REDACTED]
[2023-10-27 10:02:00] Invalid token attempt: TKN_WRONG123 from [IP_REDACTED]
"""

    with open(log_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        "The content of traffic_redacted.log does not match the expected redacted output. "
        "Ensure both the token and all IPv4 addresses are properly redacted."
    )


def test_redact_script_functionality(tmp_path):
    script_path = "/home/user/redact.sh"
    if not os.path.isfile(script_path) or not os.access(script_path, os.X_OK):
        pytest.skip("Script missing or not executable")

    test_file = tmp_path / "test.log"
    test_file.write_text("IP: 10.0.0.1, Token: TKN_7x9qL2vP, Other IP: 192.168.100.200\n")

    try:
        result = subprocess.run([script_path, str(test_file)], capture_output=True, text=True, check=True)
        output = result.stdout.strip()
        assert output == "IP: [IP_REDACTED], Token: [REDACTED], Other IP: [IP_REDACTED]", (
            "The redact.sh script did not produce the correct output when tested with a sample file. "
            "Ensure it replaces the exact token with [REDACTED] and IPv4 addresses with [IP_REDACTED]."
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of redact.sh failed: {e.stderr}")


def test_redact_script_on_fresh_unpredictable_files(tmp_path):
    token = discover_live_process_token()
    ipv4_pattern = re.compile(r"(?:[0-9]{1,3}\.){3}[0-9]{1,3}")

    for case_number in range(5):
        nonce = secrets.token_hex(12)
        addresses = [
            ".".join(str(random.SystemRandom().randint(0, 999)) for _ in range(4))
            for _ in range(3)
        ]
        other_token = "TKN_" + secrets.token_hex(7)
        source = (
            f"case={case_number}:{nonce}\n"
            f"origin {addresses[0]} used {token} twice: {token}\n"
            f"keep this token unchanged: {other_token}\n"
            f"route={addresses[1]}; peer={addresses[2]}; text={nonce}\n"
            f"plain line {secrets.token_hex(9)}\n"
        )
        expected = source.replace(token, "[REDACTED]")
        expected = ipv4_pattern.sub("[IP_REDACTED]", expected)

        test_file = tmp_path / f"unpredictable_{case_number}_{nonce}.log"
        test_file.write_text(source)
        result = subprocess.run(
            [SCRIPT_PATH, str(test_file)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"redact.sh failed: {result.stderr}"
        assert result.stdout == expected, (
            "redact.sh did not redact the actual contents of a fresh input file correctly."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
