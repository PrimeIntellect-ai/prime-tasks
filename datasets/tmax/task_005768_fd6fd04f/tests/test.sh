#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

ANALYZE = Path("/home/user/analyze.go")
LOOT = Path("/home/user/loot.txt")
MALWARE = Path("/home/user/malware.bin")
PAYLOAD = Path("/home/user/payload.enc")
EXPECTED_ORIGINAL = [
    "token_admin_9912",
    "token_user_7734",
]


def run_analyzer():
    if LOOT.exists():
        LOOT.unlink()
    result = subprocess.run(
        ["go", "run", str(ANALYZE)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "go run /home/user/analyze.go failed:\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert LOOT.is_file(), "The Go program did not create /home/user/loot.txt"


def read_loot():
    return LOOT.read_text().strip().splitlines()


def test_analyze_go_exists():
    path = "/home/user/analyze.go"
    assert os.path.isfile(path), f"Missing file: {path}. You must create the Go program here."


def test_go_program_runs_on_supplied_files():
    run_analyzer()


def test_loot_txt_exists():
    path = "/home/user/loot.txt"
    assert os.path.isfile(path), f"Missing file: {path}. Your Go program should create this file."


def test_loot_txt_content():
    path = "/home/user/loot.txt"
    assert os.path.isfile(path), f"Cannot check content, missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "token_admin_9912",
        "token_user_7734"
    ]

    assert len(content) == len(expected), f"Expected {len(expected)} tokens in {path}, but found {len(content)}."

    for i, (actual, exp) in enumerate(zip(content, expected)):
        assert actual.strip() == exp, f"Line {i+1} in {path} is incorrect. Expected '{exp}', got '{actual.strip()}'."


def test_analyzer_extracts_key_decrypts_and_parses():
    original_binary = MALWARE.read_bytes()
    original_payload = PAYLOAD.read_bytes()
    original_mode = stat.S_IMODE(MALWARE.stat().st_mode)

    key = secrets.token_bytes(4)
    while key == bytes.fromhex("7a8b9c4d"):
        key = secrets.token_bytes(4)

    expected = [f"token_{secrets.token_hex(12)}", f"token_{secrets.token_hex(12)}"]
    plaintext = (
        "POST /beacon/check HTTP/1.1\n"
        "Host: verification-c2.local\n"
        f"X-Beacon-Auth: {expected[0]}\n"
        "Content-Length: 7\n"
        "\n"
        "ok=true"
        "GET /beacon/work HTTP/1.1\n"
        "Host: verification-c2.local\n"
        f"X-Beacon-Auth: {expected[1]}\n"
        "Content-Length: 0\n"
        "\n"
    ).encode()
    encrypted = bytes(value ^ key[i % len(key)] for i, value in enumerate(plaintext))

    key_path = Path("/tmp/verifier-malware-key.bin")
    binary_path = Path("/tmp/verifier-malware.bin")
    dynamic_error = None
    try:
        key_path.write_bytes(key)
        subprocess.run(
            ["objcopy", "--update-section", f".malware_key={key_path}", str(MALWARE), str(binary_path)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        MALWARE.write_bytes(binary_path.read_bytes())
        os.chmod(MALWARE, original_mode)
        PAYLOAD.write_bytes(encrypted)

        run_analyzer()
        actual = [line.strip() for line in read_loot()]
        assert actual == expected, (
            "Analyzer did not derive the tokens from the current ELF key and encrypted HTTP payload. "
            f"Expected {expected}, got {actual}."
        )
    except BaseException as exc:
        dynamic_error = exc
    finally:
        MALWARE.write_bytes(original_binary)
        os.chmod(MALWARE, original_mode)
        PAYLOAD.write_bytes(original_payload)
        key_path.unlink(missing_ok=True)
        binary_path.unlink(missing_ok=True)

    if dynamic_error is not None:
        raise dynamic_error

    # Leave the requested output in the state produced from the supplied files.
    run_analyzer()
    assert [line.strip() for line in read_loot()] == EXPECTED_ORIGINAL
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
