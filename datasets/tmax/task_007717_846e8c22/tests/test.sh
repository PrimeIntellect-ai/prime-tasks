#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid
from pathlib import Path
import pytest

LOG_PATH = "/home/user/security.log"
RUST_SRC = "/home/user/rotate.rs"
LEAKED_KEY_TXT = "/home/user/leaked_key.txt"
PAYLOAD_JSON = "/home/user/rotation_payload.json"
RUST_BIN = "/tmp/rotate_verify_bin"


def get_expected_token():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        for line in f:
            if "[SANDBOX_ESCAPE]" in line and "Leaked token:" in line:
                return line.split("Leaked token:")[1].strip()
    pytest.fail("Could not find the leaked token in the security log.")


def test_rust_source_exists():
    assert os.path.isfile(RUST_SRC), f"Rust source file {RUST_SRC} is missing."


def test_leaked_key_file():
    expected_token = get_expected_token()
    assert os.path.isfile(LEAKED_KEY_TXT), f"Output file {LEAKED_KEY_TXT} is missing."

    with open(LEAKED_KEY_TXT, "r") as f:
        content = f.read().strip()

    assert content == expected_token, f"Expected {LEAKED_KEY_TXT} to contain '{expected_token}', but got '{content}'."


def test_rotation_payload_file():
    expected_token = get_expected_token()
    assert os.path.isfile(PAYLOAD_JSON), f"Output file {PAYLOAD_JSON} is missing."

    with open(PAYLOAD_JSON, "r") as f:
        content = f.read()

    expected_content = f'{{"action":"rotate","old_token":"{expected_token}","new_token":"RUST_SECURE_TOKEN_2024"}}'

    assert content == expected_content, f"Expected {PAYLOAD_JSON} to exactly match '{expected_content}', but got '{content}'."


def test_rust_program_compiles_and_extracts_runtime_tokens():
    log_path = Path(LOG_PATH)
    leaked_path = Path(LEAKED_KEY_TXT)
    payload_path = Path(PAYLOAD_JSON)
    original_log = log_path.read_bytes()

    compile_result = subprocess.run(
        ["rustc", RUST_SRC, "-o", RUST_BIN],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"rotate.rs failed to compile:\n{compile_result.stderr}"
    assert os.path.isfile(RUST_BIN), "rustc did not produce an executable."

    try:
        for _ in range(2):
            token = "VERIFY-" + uuid.uuid4().hex.upper()
            log_path.write_text(
                "[2026-01-01T00:00:00] [PAYLOAD_DELIVERY] Leaked token: DECOY-TOKEN\n"
                f"[2026-01-01T00:00:01] [SANDBOX_ESCAPE] Runtime test. Leaked token: {token}\n"
                "[2026-01-01T00:00:02] [CERT_VALIDATION_FAILED] Test entry.\n"
            )
            for output in (leaked_path, payload_path):
                try:
                    output.unlink()
                except FileNotFoundError:
                    pass

            run_result = subprocess.run(
                ["runuser", "-u", "user", "--", "timeout", "10s", RUST_BIN],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert run_result.returncode == 0, (
                f"Compiled Rust program failed with exit code {run_result.returncode}:\n"
                f"stdout: {run_result.stdout}\nstderr: {run_result.stderr}"
            )
            assert leaked_path.is_file(), "Rust program did not create leaked_key.txt."
            assert leaked_path.read_text().strip() == token, "Rust program did not extract the runtime token from the log."
            expected_payload = f'{{"action":"rotate","old_token":"{token}","new_token":"RUST_SECURE_TOKEN_2024"}}'
            assert payload_path.is_file(), "Rust program did not create rotation_payload.json."
            assert payload_path.read_text() == expected_payload, "Rust program generated an incorrect rotation payload."
    finally:
        log_path.write_bytes(original_log)
        for output in (leaked_path, payload_path):
            try:
                output.unlink()
            except FileNotFoundError:
                pass
        subprocess.run(
            ["runuser", "-u", "user", "--", "timeout", "10s", RUST_BIN],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
            check=False,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
