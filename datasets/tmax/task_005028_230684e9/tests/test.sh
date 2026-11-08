#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import struct
import subprocess
import time

import pytest
import requests

SERVER = "/home/user/server"
EXTRACTED = "/home/user/extracted"


def create_bkp(entries):
    payload = bytearray(b"BKP\x01")
    for filename, data in entries:
        name = filename.encode("utf-8")
        assert len(name) <= 255
        payload += struct.pack("<B", len(name))
        payload += name
        payload += struct.pack("<I", len(data))
        payload += data
    return bytes(payload)


def make_log(date, clock, event, details):
    return (
        b"=== LOG START ===\n"
        + f"Date: {date}\n".encode()
        + f"Time: {clock}\n".encode()
        + f"Event: {event}\n".encode()
        + b"Details:\n"
        + details
        + b"\n=== LOG END ===\n"
    )


def listening_socket_inodes():
    result = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            ip_hex, port_hex = local_address.split(":")
            if ip_hex == "0100007F" and int(port_hex, 16) == 8080 and state == "0A":
                result.add(fields[9])
    return result


def listener_is_server_binary():
    socket_targets = {f"socket:[{inode}]" for inode in listening_socket_inodes()}
    if not socket_targets:
        return False

    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            owns_listener = any(
                os.readlink(os.path.join(fd_dir, fd)) in socket_targets
                for fd in os.listdir(fd_dir)
            )
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
        if not owns_listener:
            continue
        try:
            if os.path.samefile(f"/proc/{pid}/exe", SERVER):
                return True
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return False


def test_00_server_binary_exists_and_is_the_listener():
    assert os.path.exists(SERVER), "Server binary /home/user/server does not exist"
    assert os.path.isfile(SERVER), "/home/user/server is not a regular file"
    assert os.access(SERVER, os.X_OK), "Server binary is not executable"

    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/server is not a compiled ELF binary"

    elf_header = subprocess.run(
        ["readelf", "-h", SERVER], capture_output=True, text=True, check=True
    ).stdout
    assert "Machine:" in elf_header and "X86-64" in elf_header, "Server is not a native x86-64 executable"
    assert "Type:" in elf_header and ("EXEC" in elf_header or "DYN" in elf_header), "Server is not an ELF executable"

    compiler_comment = subprocess.run(
        ["readelf", "-p", ".comment", SERVER], capture_output=True, text=True
    ).stdout
    assert "GCC" in compiler_comment, "Server does not contain GCC compiler provenance expected from the C implementation"

    with open(SERVER, "rb") as f:
        server_hash = hashlib.sha256(f.read()).digest()
    with open("/app/legacy_extractor", "rb") as f:
        legacy_hash = hashlib.sha256(f.read()).digest()
    assert server_hash != legacy_hash, "The unsafe legacy extractor was submitted as the server"

    deadline = time.time() + 2
    while time.time() < deadline and not listener_is_server_binary():
        time.sleep(0.05)
    assert listener_is_server_binary(), "/home/user/server is not the process listening on 127.0.0.1:8080"


def create_bkp_payload():
    filename = b"../../../home/user/hacked.log"
    data = (
        b"=== LOG START ===\n"
        b"Date: 2024-05-12\n"
        b"Time: 08:30:15\n"
        b"Event: SystemCrash\n"
        b"Details:\n"
        b"Kernel panic - not syncing\n"
        b"Out of memory\n"
        b"=== LOG END ===\n"
    )
    payload = b"BKP\x01"
    payload += struct.pack("<B", len(filename))
    payload += filename
    payload += struct.pack("<I", len(data))
    payload += data
    return payload, data


def test_01_original_server_response_and_extraction():
    payload, expected_data = create_bkp_payload()

    try:
        response = requests.post("http://127.0.0.1:8080/upload", data=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect or send request to server on port 8080: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    assert response.text.strip() == "SystemCrash", f"Expected response body 'SystemCrash', got '{response.text}'"

    hacked_log_path = "/home/user/hacked.log"
    assert not os.path.exists(hacked_log_path), "Zip Slip vulnerability detected: file was written outside the extracted directory!"

    extracted_file_path = "/home/user/extracted/20240512_083015_hacked.log"
    assert os.path.exists(extracted_file_path), f"Expected extracted file not found at {extracted_file_path}"

    with open(extracted_file_path, "rb") as f:
        actual_data = f.read()
    assert actual_data == expected_data, "Extracted file contents do not match the original payload data"


def test_02_random_multi_file_archive_is_parsed_and_sanitized():
    assert os.path.isdir(EXTRACTED), "/home/user/extracted/ directory does not exist"

    token = secrets.token_hex(10)
    event1 = "First_" + secrets.token_hex(8)
    event2 = "Second_" + secrets.token_hex(8)
    event3 = "Third_" + secrets.token_hex(8)

    specs = [
        (
            f"../../../home/user/{token}_alpha.log",
            f"{token}_alpha.log",
            "2023-11-07",
            "03:04:05",
            event1,
            b"alpha line\nEvent: detail-decoy\nDate: 1999-01-01",
        ),
        (
            f"nested/subdirectory/{token}_beta.txt",
            f"{token}_beta.txt",
            "2025-02-19",
            "21:17:43",
            event2,
            b"beta details\nwith several\nindependent lines",
        ),
        (
            f"/tmp/{token}_gamma.data",
            f"{token}_gamma.data",
            "2022-08-31",
            "12:59:01",
            event3,
            b"gamma-" + secrets.token_bytes(12).hex().encode(),
        ),
    ]

    entries = []
    expected = []
    for archived_name, basename, date, clock, event, details in specs:
        data = make_log(date, clock, event, details)
        entries.append((archived_name, data))
        stamp = date.replace("-", "") + "_" + clock.replace(":", "")
        expected.append((os.path.join(EXTRACTED, f"{stamp}_{basename}"), data, basename))

    outside_paths = [
        f"/home/user/{token}_alpha.log",
        f"/tmp/{token}_gamma.data",
    ]
    for path in outside_paths:
        assert not os.path.exists(path), f"Unexpected pre-existing randomized path: {path}"
    for path, _, _ in expected:
        assert not os.path.exists(path), f"Unexpected pre-existing randomized output: {path}"

    payload = create_bkp(entries)
    try:
        response = requests.post("http://127.0.0.1:8080/upload", data=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to submit randomized archive: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    assert response.content == event1.encode(), "Response body was not exactly the first randomized file's EventName"

    for path in outside_paths:
        assert not os.path.exists(path), f"Zip Slip wrote outside extraction directory: {path}"

    for path, data, basename in expected:
        assert os.path.isfile(path), f"Expected randomized extracted file not found: {path}"
        with open(path, "rb") as f:
            assert f.read() == data, f"Contents differ from the archive entry for {path}"
        assert not os.path.exists(os.path.join(EXTRACTED, basename)), "Unrenamed extracted file was left behind"

    assert listener_is_server_binary(), "/home/user/server stopped serving after processing requests"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
