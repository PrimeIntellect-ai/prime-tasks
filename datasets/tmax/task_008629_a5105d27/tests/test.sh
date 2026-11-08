#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid
from pathlib import Path

import pytest

BINARY = Path("/home/user/service/uploader_fixed")
SOURCE = Path("/home/user/service/uploader.cpp")
REBUILT = Path("/tmp/uploader_rebuilt")


def run_uploader(argument):
    try:
        return subprocess.run(
            [str(BINARY), argument],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Execution of uploader_fixed timed out.")


def assert_denied(argument):
    result = run_uploader(argument)
    assert result.returncode == 1, f"Expected '{argument}' to return 1, got {result.returncode}."
    assert result.stdout.strip() == "Access Denied", (
        f"Expected output to be exactly 'Access Denied' for '{argument}', "
        f"got '{result.stdout.strip()}'."
    )


@pytest.fixture(scope="session", autouse=True)
def verify_source_and_binary_match():
    assert SOURCE.is_file(), f"Source file {SOURCE} does not exist."
    assert BINARY.is_file(), f"Binary {BINARY} does not exist. Did you compile it?"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."

    with BINARY.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "uploader_fixed must be a compiled ELF executable."

    result = subprocess.run(
        ["/usr/bin/g++", "-std=c++17", "-o", str(REBUILT), str(SOURCE)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"uploader.cpp does not compile:\n{result.stderr}"
    assert BINARY.read_bytes() == REBUILT.read_bytes(), (
        "uploader_fixed is not the executable produced from the submitted uploader.cpp "
        "using the required compilation command."
    )


def test_attacker_ip_file():
    ip_file = "/home/user/attacker_ip.txt"
    assert os.path.isfile(ip_file), f"File {ip_file} does not exist."

    with open(ip_file, "r") as f:
        ip = f.read().strip()

    assert ip == "172.16.5.99", f"Expected attacker IP to be '172.16.5.99', but got '{ip}'."


def test_binary_exists_and_executable():
    assert BINARY.is_file(), f"Binary {BINARY} does not exist. Did you compile it?"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."


def test_normal_file_behavior():
    result = run_uploader("normal.log")
    assert result.returncode == 0, f"Expected normal file to return 0, got {result.returncode}."
    assert "Access Denied" not in result.stdout, "Normal file was incorrectly blocked with 'Access Denied'."


def test_path_traversal_prevention():
    assert_denied("../.ssh/id_rsa")


def test_existing_xss_scanning_logic():
    result = run_uploader("malicious.log")
    assert result.returncode == 0
    assert result.stdout == "XSS detected: Malicious log <script>alert(1)</script>\n"


def test_randomized_canonical_path_validation():
    token = uuid.uuid4().hex
    uploads = Path("/home/user/uploads")
    nested = uploads / ("inside_" + token)
    nested.mkdir()

    safe_file = nested / "safe.log"
    safe_file.write_text("ordinary line\n<script>random-test</script>\nlast line\n")

    safe_argument = f"{nested.name}/./../{nested.name}/safe.log"
    result = run_uploader(safe_argument)
    assert result.returncode == 0
    assert result.stdout == "XSS detected: <script>random-test</script>\n"

    inside_link = uploads / ("inside_link_" + token)
    inside_link.symlink_to(safe_file)
    result = run_uploader(inside_link.name)
    assert result.returncode == 0
    assert result.stdout == "XSS detected: <script>random-test</script>\n"

    outside_dir = Path("/home/user") / ("outside_" + token)
    outside_dir.mkdir()
    outside_file = outside_dir / "secret.log"
    outside_file.write_text("<script>outside-secret</script>\n")

    assert_denied(f"../{outside_dir.name}/secret.log")
    assert_denied(f"{nested.name}/../../{outside_dir.name}/secret.log")

    escape_link = uploads / ("escape_link_" + token)
    escape_link.symlink_to(outside_file)
    assert_denied(escape_link.name)

    escape_dir_link = uploads / ("escape_dir_" + token)
    escape_dir_link.symlink_to(outside_dir, target_is_directory=True)
    assert_denied(f"{escape_dir_link.name}/secret.log")

    prefix_sibling = Path("/home/user") / ("uploads_" + token)
    prefix_sibling.mkdir()
    (prefix_sibling / "secret.log").write_text("prefix collision\n")
    assert_denied(f"../{prefix_sibling.name}/secret.log")

    assert_denied(f"missing_{token}.log")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
