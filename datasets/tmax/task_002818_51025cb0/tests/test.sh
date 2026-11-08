#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

FIXTURE = "/home/user/test_fixture.c"
PAYLOAD = "/home/user/payload.bin"
OUTPUT = "/home/user/test_output.txt"
EXECUTABLE = "/tmp/test_fixture_verified"
ORIGINAL_EXPECTED = "1B 3D 3F 34 2E 02"
INPUT_BYTES = b"AgentX"


def read_output():
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} does not exist."
    with open(OUTPUT, "r", encoding="utf-8", errors="ignore") as f:
        return f.read().strip()


def run_fixture():
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"Compiled fixture exited with status {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    return read_output()


def make_payload(operation, key):
    # Same 16-byte loop structure as the supplied blob, with a verifier-chosen
    # x86 group-1 byte operation and immediate value.
    modrm = {"add": 0x44, "sub": 0x6C, "xor": 0x74}[operation]
    return bytes([
        0x48, 0x85, 0xF6, 0x74, 0x0C, 0x48, 0x89, 0xF1,
        0x80, modrm, 0x0F, 0xFF, key, 0xE2, 0xF8, 0xC3,
    ])


def expected_for(operation, key):
    if operation == "add":
        values = [(b + key) & 0xFF for b in INPUT_BYTES]
    elif operation == "sub":
        values = [(b - key) & 0xFF for b in INPUT_BYTES]
    else:
        values = [b ^ key for b in INPUT_BYTES]
    return " ".join(f"{b:02X}" for b in values)


def test_fixture_c_exists_and_contains_mmap():
    assert os.path.isfile(FIXTURE), f"File {FIXTURE} does not exist."
    with open(FIXTURE, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    assert "mmap" in content, f"File {FIXTURE} does not contain 'mmap' as required."
    for token in ("PROT_READ", "PROT_WRITE", "PROT_EXEC"):
        assert token in content, f"File {FIXTURE} does not contain '{token}' as required."


def test_compiles_executes_payload_and_writes_correct_output():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", FIXTURE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert compile_result.returncode == 0, (
        "test_fixture.c did not compile successfully: "
        + compile_result.stderr.decode(errors="replace")
    )

    with open(PAYLOAD, "rb") as f:
        original_payload = f.read()

    try:
        # Preserve the original verifier's exact assertion, but obtain the file
        # by compiling and running the submitted fixture after deleting stale output.
        actual = run_fixture()
        assert actual == ORIGINAL_EXPECTED, (
            f"Contents of {OUTPUT} are incorrect. Expected "
            f"'{ORIGINAL_EXPECTED}', got '{actual}'."
        )

        # Exercise the fixture with runtime-selected machine-code payloads so a
        # hardcoded copy of the original output cannot pass.
        for operation in ("add", "sub", "xor"):
            key = secrets.randbelow(255) + 1
            with open(PAYLOAD, "wb") as f:
                f.write(make_payload(operation, key))
            expected = expected_for(operation, key)
            actual = run_fixture()
            assert actual == expected, (
                f"Fixture did not execute the supplied machine code correctly. "
                f"Expected '{expected}', got '{actual}'."
            )
    finally:
        with open(PAYLOAD, "wb") as f:
            f.write(original_payload)
        # Restore the required final log when possible.
        if os.path.isfile(EXECUTABLE):
            try:
                run_fixture()
            except Exception:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
