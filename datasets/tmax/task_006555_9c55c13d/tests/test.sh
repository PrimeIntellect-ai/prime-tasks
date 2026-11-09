#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

WAL = Path("/home/user/data/wal.log")
OUTPUT = Path("/home/user/recovered.txt")
SOURCE = Path("/home/user/recover.c")
SUBMITTED_BINARY = Path("/home/user/recover")


def expected_from_wal(wal_text):
    state = {}
    pattern = re.compile(r'^SET "([^"]+)" "([^"]*)"$')
    for line in wal_text.splitlines():
        match = pattern.fullmatch(line)
        assert match is not None, f"Verifier generated an invalid WAL line: {line!r}"
        key, value = match.groups()
        state[key] = value
    return "".join(f"{key}={state[key]}\n" for key in sorted(state))


def run_recovery(binary, wal_text):
    WAL.write_text(wal_text)
    try:
        OUTPUT.unlink()
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [str(binary)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{binary} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT.is_file(), "The file /home/user/recovered.txt was not generated."
    actual = OUTPUT.read_text()
    expected = expected_from_wal(wal_text)
    assert actual == expected, (
        f"Recovery output from {binary} is incorrect.\n"
        f"Expected:\n{expected}\nGot:\n{actual}"
    )


def test_fixed_recovery_program():
    original_wal = WAL.read_text()

    # Preserve the original source and executable assertions.
    assert SOURCE.is_file(), "The file /home/user/recover.c is missing."
    content = SOURCE.read_text()
    assert "pthread_mutex_lock" in content, (
        "The C code does not appear to use pthread_mutex_lock to fix the race condition."
    )
    assert "pthread_mutex_unlock" in content, (
        "The C code does not appear to use pthread_mutex_unlock to fix the race condition."
    )
    assert "%s" not in content or "%[^" in content or "strtok" in content or "strchr" in content, (
        "The C code does not seem to have the fixed parsing logic for spaces."
    )

    assert SUBMITTED_BINARY.is_file(), "The executable /home/user/recover was not found."
    assert os.access(SUBMITTED_BINARY, os.X_OK), "The file /home/user/recover is not executable."
    assert SUBMITTED_BINARY.read_bytes()[:4] == b"\x7fELF", (
        "/home/user/recover is not a compiled ELF executable."
    )

    rebuilt_binary = Path("/tmp/recover_from_submitted_source")
    build = subprocess.run(
        ["gcc", "-pthread", str(SOURCE), "-o", str(rebuilt_binary)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"recover.c does not compile:\n{build.stderr}"

    try:
        # Execute both the submitted artifact and a fresh build on the original WAL.
        for binary in (SUBMITTED_BINARY, rebuilt_binary):
            run_recovery(binary, original_wal)
            expected_content = (
                "admin user=john smith\n"
                "background task=running\n"
                "error log=disk full\n"
                "system_status=online\n"
            )
            assert OUTPUT.read_text() == expected_content, (
                "The content of /home/user/recovered.txt is incorrect for the original WAL."
            )

        # Use unpredictable keys and values so a fixed recovered.txt cannot pass.
        token = secrets.token_hex(6)
        spaced_wal = "\n".join([
            f'SET "alpha key {token}" "first value"',
            f'SET "plain_{token}" "value with several spaces"',
            f'SET "zeta key {token}" "old value"',
            f'SET "middle key {token}" "another spaced value"',
            f'SET "alpha key {token}" "latest alpha value"',
            f'SET "zeta key {token}" "latest zeta value"',
        ]) + "\n"

        for binary in (SUBMITTED_BINARY, rebuilt_binary):
            run_recovery(binary, spaced_wal)

        # A larger WAL repeatedly exercises concurrent insertion and update paths.
        lines = []
        for i in range(60):
            lines.append(f'SET "race key {i:02d} {token}" "initial value {i:02d}"')
        for i in range(0, 60, 3):
            lines.append(f'SET "race key {i:02d} {token}" "latest value {i:02d} with spaces"')
        race_wal = "\n".join(lines) + "\n"

        for binary in (SUBMITTED_BINARY, rebuilt_binary):
            for _ in range(6):
                run_recovery(binary, race_wal)
    finally:
        WAL.write_text(original_wal)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
