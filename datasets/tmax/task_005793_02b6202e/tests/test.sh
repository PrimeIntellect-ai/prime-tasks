#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import pytest

EXPECTED_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILz9m/3/RkF+wY1c7E+6x3FpZ9uE1iQ1+X1hU2+dummy fake@key"
EXPECTED_OPTIONS = 'command="/home/user/isolate.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty'


def run_checked(args, timeout=15):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout, check=True)


def extract_section(binary_path):
    fd, output_path = tempfile.mkstemp(prefix="ssh_pub_")
    os.close(fd)
    os.unlink(output_path)
    try:
        run_checked(["objcopy", "--dump-section", f".ssh_pub={output_path}", binary_path])
        assert os.path.isfile(output_path), f"{binary_path} has no extractable .ssh_pub section"
        with open(output_path, "rb") as f:
            return f.read()
    finally:
        if os.path.exists(output_path):
            os.unlink(output_path)


def test_payload_exists_is_compiled_elf_and_contains_expected_section():
    payload = "/home/user/payload"
    source = "/home/user/payload.cpp"
    assert os.path.isfile(payload), f"File {payload} does not exist. Did you compile payload.cpp?"
    assert os.access(payload, os.X_OK), f"{payload} is not executable."
    with open(payload, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{payload} is not an ELF executable."

    run_checked(["readelf", "-h", payload])
    payload_section = extract_section(payload)
    assert payload_section.rstrip(b"\x00").decode("utf-8") == EXPECTED_KEY

    with tempfile.TemporaryDirectory(prefix="payload_reference_") as td:
        reference = os.path.join(td, "payload")
        run_checked(["g++", source, "-o", reference], timeout=30)
        assert payload_section == extract_section(reference), \
            "The compiled payload's .ssh_pub section does not match payload.cpp."

        submitted_run = run_checked([payload])
        reference_run = run_checked([reference])
        assert submitted_run.stdout == reference_run.stdout
        assert submitted_run.stderr == reference_run.stderr


def test_found_key_pub_extracted():
    found_key_path = "/home/user/found_key.pub"
    assert os.path.isfile(found_key_path), f"File {found_key_path} does not exist. Did you extract the section?"

    with open(found_key_path, "rb") as f:
        content = f.read()

    # Preserve the original assertion.
    content_str = content.decode('utf-8', errors='ignore').strip('\x00').strip()
    assert EXPECTED_KEY in content_str, f"{found_key_path} does not contain the expected SSH key. Found: {content_str}"

    # The requested extraction must be the exact contents of the payload section.
    assert content == extract_section("/home/user/payload"), \
        f"{found_key_path} is not an exact extraction of /home/user/payload's .ssh_pub section."


def test_authorized_keys_hardened():
    auth_keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(auth_keys_path), f"File {auth_keys_path} does not exist."

    with open(auth_keys_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_entry = f"{EXPECTED_OPTIONS} {EXPECTED_KEY}"

    # Preserve the original assertion.
    found = any(expected_entry in line for line in lines)
    assert found, f"The expected hardened SSH key entry was not found in {auth_keys_path}. Ensure the options are prepended exactly as requested."

    assert expected_entry in lines, \
        "The hardened key must appear as an exact authorized_keys entry without extra options or trailing data."


def test_elf_offset_result():
    offset_file_path = "/home/user/elf_offset.txt"
    assert os.path.isfile(offset_file_path), f"File {offset_file_path} does not exist. Did you run your scanner?"

    with open(offset_file_path, "r") as f:
        content = f.read().strip()

    # Preserve the original assertion for the supplied capture.
    assert content == "1842", f"The offset written to {offset_file_path} is incorrect. Expected '1842', got '{content}'."


def test_scanner_cpp_exists():
    scanner_path = "/home/user/scanner.cpp"
    assert os.path.isfile(scanner_path), f"File {scanner_path} does not exist. You must write the C++ scanner program."

    with open(scanner_path, "r") as f:
        content = f.read()

    assert len(content.strip()) > 0, f"{scanner_path} is empty."
    assert "main" in content, f"{scanner_path} does not appear to be a valid C++ program (no main function found)."


def test_scanner_compiles_and_finds_first_magic_on_derived_inputs():
    scanner_source = "/home/user/scanner.cpp"
    traffic_path = "/home/user/traffic.dat"
    output_path = "/home/user/elf_offset.txt"

    with tempfile.TemporaryDirectory(prefix="scanner_test_") as td:
        scanner_binary = os.path.join(td, "scanner")
        run_checked(["g++", "-std=c++17", scanner_source, "-o", scanner_binary], timeout=30)

        with open(traffic_path, "rb") as f:
            original_traffic = f.read()
        original_output = None
        if os.path.exists(output_path):
            with open(output_path, "rb") as f:
                original_output = f.read()

        cases = []
        supplied = original_traffic
        cases.append(supplied)

        data_at_zero = bytearray(b"Q" * 257)
        data_at_zero[0:4] = b"\x7fELF"
        cases.append(bytes(data_at_zero))

        data_middle = bytearray((i * 37 + 11) % 251 for i in range(6137))
        data_middle[731:735] = b"\x7fELF"
        cases.append(bytes(data_middle))

        data_multiple = bytearray(b"Z" * 10000)
        data_multiple[123:127] = b"\x7fELF"
        data_multiple[8123:8127] = b"\x7fELF"
        cases.append(bytes(data_multiple))

        try:
            for data in cases:
                expected = data.find(b"\x7fELF")
                assert expected >= 0
                with open(traffic_path, "wb") as f:
                    f.write(data)
                if os.path.exists(output_path):
                    os.unlink(output_path)

                run_checked([scanner_binary], timeout=10)
                assert os.path.isfile(output_path), \
                    "The compiled scanner did not create /home/user/elf_offset.txt."
                with open(output_path, "r") as f:
                    actual = f.read().strip()
                assert actual == str(expected), \
                    f"Scanner returned {actual!r}; first ELF magic is at byte {expected}."
        finally:
            with open(traffic_path, "wb") as f:
                f.write(original_traffic)
            if original_output is None:
                if os.path.exists(output_path):
                    os.unlink(output_path)
            else:
                with open(output_path, "wb") as f:
                    f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
