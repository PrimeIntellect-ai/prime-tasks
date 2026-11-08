#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import sys

SCRIPT_PATH = "/home/user/clean_logs.py"
RAW_PATH = "/home/user/storage/raw_app.log"
PAYLOAD_PATH = "/home/user/storage/payload.bin"
CLEANED_PATH = "/home/user/storage/cleaned_app.log"


def test_clean_logs_script_exists_and_is_python():
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"File {SCRIPT_PATH} is not a regular file."

    with open(SCRIPT_PATH, "rb") as f:
        source = f.read()
    compile(source, SCRIPT_PATH, "exec")


def test_payload_bin_exists_and_content():
    payload_path = "/home/user/storage/payload.bin"
    assert os.path.isfile(payload_path), f"File {payload_path} does not exist."

    expected_hex = (
        "5468697320697320612073656372"
        "65742062696e617279207061796c"
        "6f61642068696464656e20696e20"
        "746865206c6f67732e0a"
    )
    expected_bytes = bytes.fromhex(expected_hex)

    with open(payload_path, "rb") as f:
        content = f.read()

    assert content == expected_bytes, "The content of payload.bin does not match the expected decoded binary data."


def test_cleaned_app_log_exists_and_content():
    log_path = "/home/user/storage/cleaned_app.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."

    expected_content = (
        "[2023-10-24 08:12:01] INFO System startup initiated.\n"
        "[2023-10-24 08:12:05] WARN Storage latency detected on /dev/sda1.\n"
        "[2023-10-24 08:15:30] ERROR Fatal kernel panic simulated.\n"
        "[DUMP EXTRACTED TO PAYLOAD.BIN]\n"
        "[2023-10-24 08:16:00] INFO Rebooting system...\n"
        "[2023-10-24 08:16:15] INFO System back online.\n"
    )

    with open(log_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), "The content of cleaned_app.log does not match the expected output."


def test_script_processes_fresh_unpredictable_input_when_executed():
    payload = secrets.token_bytes(97)
    token = secrets.token_hex(12)
    encoded = payload.hex()
    hex_block = (
        "  " + encoded[:41] + " \n"
        "\t" + encoded[41:103] + "\n"
        " " + encoded[103:157] + "   \n"
        + encoded[157:] + "\n"
    )

    before = (
        f"[{token}] INFO dynamic fixture begins.\n"
        "A normal log line that must remain unchanged.\n"
    )
    after = (
        "Another normal log line that must remain unchanged.\n"
        f"[{token}] INFO dynamic fixture ends.\n"
    )
    raw_content = before + "===BEGIN DUMP===\n" + hex_block + "===END DUMP===\n" + after
    expected_cleaned = before + "[DUMP EXTRACTED TO PAYLOAD.BIN]\n" + after

    with open(RAW_PATH, "w") as f:
        f.write(raw_content)

    for path in (PAYLOAD_PATH, CLEANED_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )

    assert os.path.isfile(PAYLOAD_PATH), "Executing the script did not create payload.bin."
    assert os.path.isfile(CLEANED_PATH), "Executing the script did not create cleaned_app.log."

    with open(PAYLOAD_PATH, "rb") as f:
        actual_payload = f.read()
    assert actual_payload == payload, "The script did not decode the fresh dump correctly."

    with open(CLEANED_PATH, "r") as f:
        actual_cleaned = f.read()
    assert actual_cleaned == expected_cleaned, "The script did not clean the fresh log correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
