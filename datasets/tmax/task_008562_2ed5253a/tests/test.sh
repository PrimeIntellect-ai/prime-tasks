#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import string
import struct
import subprocess
import tempfile

import pytest

INCIDENT_DIR = "/home/user/incident"
BUILD_SCRIPT = os.path.join(INCIDENT_DIR, "build.sh")
EXECUTABLE = os.path.join(INCIDENT_DIR, "telemetry_parser")


@pytest.fixture(scope="session", autouse=True)
def rebuild_from_script():
    assert os.path.isfile(BUILD_SCRIPT), f"The build script '{BUILD_SCRIPT}' was not found."

    # Remove any pre-existing artifact so the verifier checks that build.sh
    # itself creates the requested executable.
    if os.path.lexists(EXECUTABLE):
        assert not os.path.isdir(EXECUTABLE), f"'{EXECUTABLE}' is a directory."
        os.unlink(EXECUTABLE)

    result = subprocess.run(
        ["/bin/bash", BUILD_SCRIPT],
        cwd=INCIDENT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_executable_compiled():
    path = "/home/user/incident/telemetry_parser"
    assert os.path.isfile(path), f"The executable '{path}' was not found. Did you fix build.sh and run it?"
    assert os.access(path, os.X_OK), f"The file '{path}' is not executable."

    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"The executable '{path}' must be a regular file."
    with open(path, "rb") as f:
        binary = f.read()
    assert binary.startswith(b"\x7fELF"), f"The file '{path}' is not a compiled ELF executable."
    assert b"telemetry_parser.c" in binary, (
        "The executable does not contain the debug/source metadata expected from compiling telemetry_parser.c."
    )


def test_compiled_program_behaviour():
    # Exercise the newly built service with verifier-generated packet values.
    alphabet = string.ascii_uppercase + string.digits
    device_id = "T-" + "".join(secrets.choice(alphabet) for _ in range(8))
    payload_length = secrets.randbelow(48) + 1
    packet = device_id.encode("ascii").ljust(16, b"\x00")
    packet += struct.pack("<i", payload_length)
    packet += secrets.token_bytes(payload_length)

    with tempfile.TemporaryDirectory() as workdir:
        with open(os.path.join(workdir, "telemetry.tmp"), "wb") as f:
            f.write(packet)

        result = subprocess.run(
            [EXECUTABLE],
            cwd=workdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )

    assert result.returncode == 0, (
        f"The compiled telemetry_parser failed on a valid packet. stderr:\n{result.stderr}"
    )
    expected = f"Processed {device_id}, score: {float(payload_length ** 2):.6f}\n"
    assert result.stdout == expected, (
        "The built executable does not behave like telemetry_parser.c for a verifier-generated packet.\n"
        f"Expected stdout: {expected!r}\nGot: {result.stdout!r}"
    )


def test_postmortem_file_exists():
    path = "/home/user/postmortem.txt"
    assert os.path.isfile(path), f"The post-mortem report '{path}' was not created."


def test_postmortem_contents():
    path = "/home/user/postmortem.txt"
    assert os.path.isfile(path), f"The post-mortem report '{path}' was not created."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = "DeviceID: SENSOR-X99\nLength: 9999999"

    # Normalize line endings and strip trailing whitespaces
    content_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines()]

    assert content_lines == expected_lines, (
        f"The contents of '{path}' do not match the expected format or values.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
