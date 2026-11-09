#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import tarfile
from collections import Counter

import pytest

HOME = "/home/user"
PORTS_FILE = f"{HOME}/vnc_ports.txt"
STATUS_FILE = f"{HOME}/restored_vnc_status.txt"
SOURCE_FILE = f"{HOME}/test_connectivity.rs"
BINARY_FILE = f"{HOME}/test_connectivity"
ARCHIVE_FILE = f"{HOME}/archive/sys_backup.tar.gz"


def test_extracted_files_exist_and_match_archive():
    log_path = f"{HOME}/restored/qemu_vnc.log"
    disk_path = f"{HOME}/restored/disk.img"

    assert os.path.exists(log_path), f"Extracted log file is missing: {log_path}"
    assert os.path.isfile(log_path), f"Path is not a file: {log_path}"
    assert os.path.exists(disk_path), f"Extracted disk image is missing: {disk_path}"
    assert os.path.isfile(disk_path), f"Path is not a file: {disk_path}"

    assert os.path.isfile(ARCHIVE_FILE), f"Backup archive is missing: {ARCHIVE_FILE}"
    with tarfile.open(ARCHIVE_FILE, "r:gz") as archive:
        regular_members = {
            member.name.lstrip("./"): member
            for member in archive.getmembers()
            if member.isfile()
        }
        assert set(regular_members) == {"qemu_vnc.log", "disk.img"}
        for name, restored_path in {
            "qemu_vnc.log": log_path,
            "disk.img": disk_path,
        }.items():
            archived = archive.extractfile(regular_members[name])
            assert archived is not None
            with archived, open(restored_path, "rb") as restored:
                assert restored.read() == archived.read(), f"{restored_path} does not match the archive"


def test_vnc_ports_extracted():
    assert os.path.exists(PORTS_FILE), f"Ports file is missing: {PORTS_FILE}"

    with open(PORTS_FILE, "r") as f:
        content = f.read().strip()
    ports = [line.strip() for line in content.splitlines() if line.strip()]
    expected_ports = ["5901", "5902", "5905"]
    assert ports == expected_ports, f"Expected ports {expected_ports}, but got {ports}"

    phrase = "VNC server running on 127.0.0.1:"
    with open(f"{HOME}/restored/qemu_vnc.log", "r") as f:
        derived_ports = [line.split(phrase, 1)[1].strip() for line in f if phrase in line]
    assert ports == derived_ports, "vnc_ports.txt was not correctly derived from the restored log"
    assert all(re.fullmatch(r"[0-9]+", port) for port in ports)


def run_and_check(artifact, ports, up_ports):
    with open(PORTS_FILE, "w") as f:
        f.write("".join(f"{port}\n" for port in ports))
    if os.path.exists(STATUS_FILE):
        os.remove(STATUS_FILE)

    result = subprocess.run(
        [artifact], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{artifact} exited with {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(STATUS_FILE), f"{artifact} did not create {STATUS_FILE}"
    with open(STATUS_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        f"PORT {port} IS {'UP' if port in up_ports else 'DOWN'}"
        for port in ports
    ]
    assert Counter(lines) == Counter(expected), (
        f"Expected status lines {expected}, but got {lines}"
    )


def make_listening_socket():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    sock.listen(16)
    return sock


def test_rust_program_and_status_output(tmp_path):
    assert os.path.exists(SOURCE_FILE), f"Rust source file missing: {SOURCE_FILE}"
    assert os.path.isfile(SOURCE_FILE), f"Rust source path is not a file: {SOURCE_FILE}"
    assert os.path.getsize(SOURCE_FILE) > 0, "Rust source file is empty"

    assert os.path.exists(BINARY_FILE), f"Compiled Rust binary missing: {BINARY_FILE}"
    assert os.path.isfile(BINARY_FILE), f"Compiled Rust binary is not a regular file: {BINARY_FILE}"
    assert os.access(BINARY_FILE, os.X_OK), f"Compiled Rust binary is not executable: {BINARY_FILE}"
    with open(BINARY_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled Rust binary is not an ELF executable"

    rebuilt_binary = str(tmp_path / "test_connectivity_rebuilt")
    compile_result = subprocess.run(
        ["rustc", SOURCE_FILE, "-o", rebuilt_binary],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"Rust source does not compile: {compile_result.stderr}"
    assert os.access(rebuilt_binary, os.X_OK)

    original_ports = open(PORTS_FILE, "rb").read()
    listeners = [make_listening_socket(), make_listening_socket()]
    up_ports = {str(sock.getsockname()[1]) for sock in listeners}

    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    down_port = str(probe.getsockname()[1])
    probe.close()
    while down_port in up_ports:
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.bind(("127.0.0.1", 0))
        down_port = str(probe.getsockname()[1])
        probe.close()

    dynamic_ports = [str(listeners[0].getsockname()[1]), down_port, str(listeners[1].getsockname()[1])]
    try:
        run_and_check(BINARY_FILE, dynamic_ports, up_ports)
        run_and_check(rebuilt_binary, dynamic_ports, up_ports)
    finally:
        for sock in listeners:
            sock.close()
        with open(PORTS_FILE, "wb") as f:
            f.write(original_ports)

    canonical_listener = None
    try:
        canonical_listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        canonical_listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        canonical_listener.bind(("127.0.0.1", 5902))
        canonical_listener.listen(16)
    except OSError:
        if canonical_listener is not None:
            canonical_listener.close()
        canonical_listener = None

    try:
        run_and_check(BINARY_FILE, ["5901", "5902", "5905"], {"5902"})
    finally:
        if canonical_listener is not None:
            canonical_listener.close()

    assert os.path.exists(STATUS_FILE), f"Status output file missing: {STATUS_FILE}"
    with open(STATUS_FILE, "r") as f:
        content = f.read().strip()
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [
        "PORT 5901 IS DOWN",
        "PORT 5902 IS UP",
        "PORT 5905 IS DOWN",
    ]
    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {STATUS_FILE}"
    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines, but got {len(lines)} in {STATUS_FILE}"
    )


def test_fstab_mock_output():
    fstab_file = f"{HOME}/fstab_test"
    assert os.path.exists(fstab_file), f"Fstab test file missing: {fstab_file}"

    with open(fstab_file, "r") as f:
        content = f.read().strip()
    lines = [line for line in content.splitlines() if line.strip()]
    assert len(lines) == 1, f"Expected exactly one line in {fstab_file}, but got {len(lines)}"

    tokens = lines[0].split()
    expected_tokens = [
        "/home/user/restored/disk.img",
        "/mnt/restored",
        "ext4",
        "loop,ro",
        "0",
        "0",
    ]
    assert tokens == expected_tokens, f"Expected fstab tokens {expected_tokens}, but got {tokens}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
