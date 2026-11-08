#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import os
import re
import secrets
import stat
import subprocess

import pytest

TRAFFIC_PATH = "/home/user/traffic.txt"
REASSEMBLED_PATH = "/home/user/reassembled.bin"
EVADER_PATH = "/home/user/evader.go"
PAYLOAD_PATH = "/home/user/payload.bin"
SIGNATURE = b"IDS_CATCH_ME"
REPLACEMENT = b"EVASION_DONE"


def payload_from_traffic():
    chunks = {}
    pattern = re.compile(rb"^Cookie: sequence=(\d+); data=([0-9A-Fa-f]+)\r?$", re.MULTILINE)
    with open(TRAFFIC_PATH, "rb") as f:
        traffic = f.read()

    matches = pattern.findall(traffic)
    assert matches, "No payload chunks were found in traffic.txt."

    for sequence_raw, hex_data in matches:
        sequence = int(sequence_raw)
        assert sequence not in chunks, f"Duplicate sequence number {sequence} in traffic.txt."
        try:
            chunks[sequence] = binascii.unhexlify(hex_data)
        except (binascii.Error, ValueError) as exc:
            pytest.fail(f"Invalid hexadecimal data in sequence {sequence}: {exc}")

    assert sorted(chunks) == list(range(len(chunks))), "Traffic chunk sequence is not contiguous from zero."
    return b"".join(chunks[i] for i in range(len(chunks)))


def test_evader_go_exists():
    """Verify that /home/user/evader.go exists."""
    assert os.path.isfile(EVADER_PATH), "/home/user/evader.go does not exist."


def test_reassembled_binary_matches_traffic():
    """Verify that reassembled.bin is the ELF reconstructed from the traffic chunks."""
    assert os.path.isfile(REASSEMBLED_PATH), f"{REASSEMBLED_PATH} does not exist."
    expected = payload_from_traffic()
    with open(REASSEMBLED_PATH, "rb") as f:
        actual = f.read()
    assert actual == expected, "reassembled.bin does not exactly match the ordered traffic chunks."
    assert actual.startswith(b"\x7fELF"), "reassembled.bin is not an ELF file."
    assert SIGNATURE in actual, "The expected IDS signature is absent from reassembled.bin."


def test_evader_go_processes_reassembled_input():
    """Execute evader.go against a randomized input variant and verify its exact transformation."""
    assert os.path.isfile(EVADER_PATH), f"{EVADER_PATH} does not exist."
    assert os.path.isfile(REASSEMBLED_PATH), f"{REASSEMBLED_PATH} does not exist."
    assert os.path.isfile(PAYLOAD_PATH), f"{PAYLOAD_PATH} does not exist."

    with open(REASSEMBLED_PATH, "rb") as f:
        original_reassembled = f.read()
    with open(PAYLOAD_PATH, "rb") as f:
        original_payload = f.read()
    original_mode = stat.S_IMODE(os.stat(PAYLOAD_PATH).st_mode)

    marker = b"VERIFIER_PROBE_" + secrets.token_bytes(32)
    probe = original_reassembled + marker
    expected = probe.replace(SIGNATURE, REPLACEMENT)

    try:
        with open(REASSEMBLED_PATH, "wb") as f:
            f.write(probe)
        with open(PAYLOAD_PATH, "wb") as f:
            f.write(b"sentinel")
        os.chmod(PAYLOAD_PATH, 0o700)

        result = subprocess.run(
            ["go", "run", EVADER_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f"evader.go failed when executed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        with open(PAYLOAD_PATH, "rb") as f:
            generated = f.read()
        assert generated == expected, (
            "evader.go did not read reassembled.bin and produce its exact size-preserving signature replacement."
        )
    finally:
        with open(REASSEMBLED_PATH, "wb") as f:
            f.write(original_reassembled)
        with open(PAYLOAD_PATH, "wb") as f:
            f.write(original_payload)
        os.chmod(PAYLOAD_PATH, original_mode)


def test_payload_bin_exists_and_permissions():
    """Verify that /home/user/payload.bin exists and has 0700 permissions."""
    assert os.path.isfile(PAYLOAD_PATH), f"{PAYLOAD_PATH} does not exist."
    st = os.stat(PAYLOAD_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Permissions of {PAYLOAD_PATH} are {oct(perms)}, expected 0o700."


def test_payload_is_exact_modified_elf():
    """Verify payload.bin is exactly reassembled.bin with only the required replacement."""
    with open(REASSEMBLED_PATH, "rb") as f:
        reassembled = f.read()
    with open(PAYLOAD_PATH, "rb") as f:
        payload = f.read()
    expected = reassembled.replace(SIGNATURE, REPLACEMENT)
    assert payload == expected, "payload.bin is not the exact transformed reassembled ELF."
    assert payload.startswith(b"\x7fELF"), "payload.bin is not an ELF file."
    assert len(payload) == len(reassembled), "The transformed payload changed size."


def test_payload_execution_output():
    """Verify that executing /home/user/payload.bin produces the expected output."""
    try:
        result = subprocess.run([PAYLOAD_PATH], capture_output=True, text=True, timeout=5)
        output = result.stdout.strip()
        expected = "Payload executing! Status: EVASION_DONE"
        assert expected in output, f"Execution output was '{output}', expected to contain '{expected}'."
    except Exception as e:
        pytest.fail(f"Failed to execute {PAYLOAD_PATH}: {e}")


def test_payload_no_ids_signature():
    """Verify that the IDS signature is no longer in /home/user/payload.bin."""
    with open(PAYLOAD_PATH, "rb") as f:
        content = f.read()
    assert SIGNATURE not in content, "The signature 'IDS_CATCH_ME' is still present in payload.bin."
    assert REPLACEMENT in content, "The replacement string 'EVASION_DONE' was not found in payload.bin."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
