#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import pytest

SOURCE = "/home/user/ws_interp.c"
BINARY = "/home/user/ws_interp"
PAYLOAD = "/home/user/payload.bin"
LOG = "/home/user/execution_log.txt"
VERIFIED_BINARY = "/tmp/ws_interp_verified"


def run_program(binary, payload):
    return subprocess.run(
        [binary], input=payload, capture_output=True, timeout=10
    )


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF binary."


def make_case(frame_count):
    frames = []
    expected = 0
    for i in range(frame_count):
        opcode = 0x01 if i % 3 != 1 else secrets.choice([0x02, 0x7f, 0xff])
        payload = secrets.randbelow(2001) - 1000
        frames.append(struct.pack("=Bi", opcode, payload))
        if opcode == 0x01:
            expected += payload
    return b"".join(frames), f"FINAL_ACCUMULATOR: {expected}\n".encode()


@pytest.fixture(scope="session")
def verified_binary():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    result = subprocess.run(
        ["gcc", SOURCE, "-o", VERIFIED_BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Source did not compile with the required gcc command.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert result.stderr == "", f"Compilation produced warnings/errors:\n{result.stderr}"
    assert os.path.isfile(VERIFIED_BINARY) and os.access(VERIFIED_BINARY, os.X_OK)
    assert_elf(VERIFIED_BINARY)
    return VERIFIED_BINARY


def test_execution_log():
    assert os.path.isfile(LOG), f"Output file {LOG} is missing."
    with open(LOG, "r") as f:
        content = f.read().strip()
    assert content == "FINAL_ACCUMULATOR: 42", (
        f"Expected 'FINAL_ACCUMULATOR: 42' in {LOG}, but got '{content}'"
    )

    with open(PAYLOAD, "rb") as f:
        result = subprocess.run([BINARY], stdin=f, capture_output=True, timeout=10)
    assert result.returncode == 0, f"Compiled program failed on payload: {result.stderr!r}"
    with open(LOG, "rb") as f:
        logged = f.read()
    assert logged == result.stdout, "execution_log.txt is not the output of the compiled program."


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    assert_elf(BINARY)


def test_no_memory_leaks():
    assert os.path.isfile(BINARY), "Binary missing, cannot run valgrind."
    assert os.path.isfile(PAYLOAD), "Payload missing, cannot run valgrind."

    cmd = [
        "valgrind",
        "--leak-check=full",
        "--error-exitcode=1",
        BINARY,
    ]
    with open(PAYLOAD, "rb") as f_in:
        result = subprocess.run(cmd, stdin=f_in, capture_output=True, text=True, timeout=30)

    stderr = result.stderr.lower()
    assert "definitely lost: 0 bytes" in stderr, (
        "Memory leak detected: 'definitely lost: 0 bytes' not found in valgrind output.\n"
        f"Valgrind stderr:\n{result.stderr}"
    )
    assert result.returncode == 0, (
        f"Valgrind reported errors or the program crashed. Return code: {result.returncode}\n"
        f"Stderr:\n{result.stderr}"
    )


def test_source_and_installed_binary_process_unpredictable_streams(verified_binary):
    cases = [make_case(n) for n in (2, 5, 9, 13)]
    for payload, expected in cases:
        for binary in (verified_binary, BINARY):
            result = run_program(binary, payload)
            assert result.returncode == 0, (
                f"{binary} failed on a generated frame stream: {result.stderr!r}"
            )
            assert result.stdout == expected, (
                f"{binary} produced {result.stdout!r}; expected {expected!r}"
            )


def test_compiled_source_is_completely_leak_free(verified_binary):
    payload, expected = make_case(17)
    cmd = [
        "valgrind",
        "--leak-check=full",
        "--show-leak-kinds=all",
        "--errors-for-leak-kinds=all",
        "--error-exitcode=1",
        verified_binary,
    ]
    result = subprocess.run(
        cmd, input=payload, capture_output=True, timeout=30
    )
    stderr = result.stderr.decode(errors="replace")
    assert result.stdout == expected, (
        f"Source-built interpreter returned {result.stdout!r}; expected {expected!r}"
    )
    assert result.returncode == 0, f"Valgrind reported an error:\n{stderr}"
    assert "definitely lost: 0 bytes" in stderr.lower(), stderr
    assert "all heap blocks were freed" in stderr.lower(), (
        f"Not all allocated frames were freed:\n{stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
