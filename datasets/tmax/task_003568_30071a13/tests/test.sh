#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import secrets
import subprocess
import tempfile

import pytest

DECODE = "/home/user/decode"
SOURCE = "/home/user/decode.cpp"
TRAFFIC = "/home/user/traffic.log"
EXPECTED_KEY = b"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC3X attacker@evil.com"
MALICIOUS_PAYLOAD = b'''{"user":"admin","role":"admin","cmd":"mkdir -p ~/.ssh; echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC3X attacker@evil.com' >> ~/.ssh/authorized_keys"}'''


def run_decoder(program, log_path):
    result = subprocess.run(
        [program, log_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Decoder {program} exited with {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


@pytest.fixture(scope="session")
def rebuilt_decoder():
    assert os.path.isfile(SOURCE), f"Source file not found: {SOURCE}"
    output = "/tmp/decode_from_submitted_source"
    result = subprocess.run(
        ["g++", SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "decode.cpp does not compile:\n" + result.stderr.decode(errors="replace")
    )
    return output


def test_decode_compiled():
    """Test that decode.cpp was compiled to an executable."""
    executable_path = DECODE
    assert os.path.isfile(executable_path), f"Executable not found: {executable_path}"
    assert os.access(executable_path, os.X_OK), f"File is not executable: {executable_path}"
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "decode is not a compiled ELF executable"


def test_decoder_handles_base64url(rebuilt_decoder):
    """Exercise both the submitted binary and submitted source on derived inputs."""
    payloads = [b"\xfb", b"\xff", b"\xfb\xff"]

    # Add unpredictable cases whose expected answers are derived at verification time.
    saw_dash = False
    saw_underscore = False
    while len(payloads) < 15 or not (saw_dash and saw_underscore):
        raw = secrets.token_bytes(secrets.choice((1, 2, 3)))
        encoded = base64.urlsafe_b64encode(raw).rstrip(b"=")
        if b"-" in encoded or b"_" in encoded:
            payloads.append(raw)
            saw_dash |= b"-" in encoded
            saw_underscore |= b"_" in encoded

    lines = []
    for raw in payloads:
        encoded = base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")
        lines.append(f"Authorization: Bearer header.{encoded}.signature\n")

    with tempfile.NamedTemporaryFile("w", delete=False) as log:
        log.writelines(lines)
        log_path = log.name

    try:
        expected = b"".join(raw + b"\n" for raw in payloads)
        for program in (DECODE, rebuilt_decoder):
            assert run_decoder(program, log_path) == expected, (
                f"{program} did not correctly decode Base64URL payloads with "
                "'-', '_', and omitted padding"
            )
    finally:
        os.unlink(log_path)


def test_decoder_parses_supplied_traffic(rebuilt_decoder):
    """Actually run both decoders against the supplied intercepted traffic."""
    assert os.path.isfile(TRAFFIC), f"Traffic log not found: {TRAFFIC}"
    for program in (DECODE, rebuilt_decoder):
        output = run_decoder(program, TRAFFIC)
        assert MALICIOUS_PAYLOAD + b"\n" in output, (
            f"{program} did not recover the forged JWT payload from traffic.log"
        )


def test_rogue_pub_exists_and_correct():
    """Test that rogue.pub exists and contains the correct SSH public key."""
    file_path = "/home/user/rogue.pub"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "rb") as f:
        content = f.read().strip()

    expected_key = EXPECTED_KEY
    assert content == expected_key, (
        f"Incorrect content in {file_path}.\n"
        f"Expected: '{expected_key.decode()}'\n"
        f"Actual:   '{content.decode(errors='replace')}'"
    )

    match = re.search(rb"ssh-rsa [A-Za-z0-9+/=]+ [^'\"\\\s]+", MALICIOUS_PAYLOAD)
    assert match is not None and content == match.group(0), (
        "rogue.pub is not exactly the SSH key embedded in the forged payload"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
