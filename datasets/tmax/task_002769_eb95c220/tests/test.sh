#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import signal
import socket
import subprocess
import time

import pytest

BASE = "/home/user/sec_api"
BINARY = os.path.join(BASE, "build/server")


def listening_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def pids_owning(inodes):
    owners = set()
    targets = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in targets:
                        owners.add(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def stop_port_8080():
    pids = pids_owning(listening_inodes())
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listening_inodes() and time.time() < deadline:
        time.sleep(0.05)
    for pid in pids_owning(listening_inodes()):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listening_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listening_inodes(), "Could not free TCP port 8080 for verification."


def wait_for_owned_listener(proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        assert proc.poll() is None, "Server exited before listening on port 8080."
        inodes = listening_inodes()
        if inodes and proc.pid in pids_owning(inodes):
            return
        time.sleep(0.05)
    pytest.fail("The executed server did not listen on port 8080.")


def request(body):
    req = (
        b"POST /analyze HTTP/1.1\r\n"
        b"Host: 127.0.0.1:8080\r\n"
        b"Connection: close\r\n"
        b"Content-Type: text/plain\r\n"
        + f"Content-Length: {len(body)}\r\n\r\n".encode()
        + body
    )
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(req)
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    raw = b"".join(chunks)
    head, separator, response_body = raw.partition(b"\r\n\r\n")
    assert separator, f"Malformed HTTP response: {raw!r}"
    status = int(head.split(b"\r\n", 1)[0].split()[1])
    return status, response_body


def exercise_server(binary):
    stop_port_8080()
    proc = subprocess.Popen([binary], cwd=os.path.dirname(binary), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_owned_listener(proc)

        # Minimal `mov eax, 42; ret`, derived and encoded by the verifier.
        valid = bytes([0xB8]) + (42).to_bytes(4, "little") + bytes([0xC3])
        assert request(base64.b64encode(valid)) == (200, b"Payload valid and correct")

        # Random-length safe payload which cannot match either accepted program.
        safe_incorrect = bytes(secrets.choice((0x90, 0x91, 0x40, 0x41)) for _ in range(secrets.randbelow(12) + 2))
        assert request(base64.b64encode(safe_incorrect)) == (200, b"Payload valid but incorrect behavior")

        # The final bytes are significant: the old decoder's pop_back bug removes
        # the 0x05 and incorrectly allows this syscall sequence.
        prefix = bytes([0x90]) * (secrets.randbelow(5) + 1)
        unsafe = prefix + bytes([0x0F, 0x05])
        assert request(base64.b64encode(unsafe)) == (403, b"Unsafe instructions detected")

        assert request(b"@@@not-base64@@@") == (400, b"Empty or invalid payload")
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)


def test_directories_created():
    assert os.path.isdir(BASE), f"Directory {BASE} is missing."
    for sub in ["src", "include", "patches", "build"]:
        dir_path = os.path.join(BASE, sub)
        assert os.path.isdir(dir_path), f"Subdirectory {dir_path} is missing."


def test_files_moved_and_patched():
    src_file = os.path.join(BASE, "src/api_server.cpp")
    include_file = os.path.join(BASE, "include/payload_validator.h")
    patch_file = os.path.join(BASE, "patches/b64_decoder.patch")

    assert os.path.isfile(src_file), f"Source file {src_file} is missing. Was it moved?"
    assert os.path.isfile(include_file), f"Header file {include_file} is missing. Was it moved?"
    assert os.path.isfile(patch_file), f"Patch file {patch_file} is missing. Was it moved?"

    with open(src_file) as f:
        content = f.read()
    assert "BUG: Drops trailing characters" not in content, "The patch was not successfully applied to api_server.cpp."
    assert "out.pop_back()" not in content, "The patch was not successfully applied to api_server.cpp."
    assert '#include "payload_validator.h"' in content

    # Reversing the supplied patch must cleanly restore its removed hunk.
    reversed_patch = subprocess.run(
        ["patch", "--batch", "--dry-run", "-R", "-p0", "-i", patch_file],
        cwd=os.path.dirname(src_file), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert reversed_patch.returncode == 0, "The supplied patch was not actually applied to api_server.cpp:\n" + reversed_patch.stdout

    for name in ("api_server.cpp", "payload_validator.h", "b64_decoder.patch"):
        assert not os.path.exists(os.path.join("/home/user/legacy_tools", name)), f"{name} was copied rather than moved."


def test_server_compiled():
    assert os.path.isfile(BINARY), f"Compiled server executable {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "build/server is not a compiled ELF executable."


def test_server_was_started_by_agent():
    inodes = listening_inodes()
    assert inodes, "No server is listening on port 8080."
    owners = pids_owning(inodes)
    expected = os.path.realpath(BINARY)
    assert any(os.path.realpath(f"/proc/{pid}/exe") == expected for pid in owners), "The submitted build/server is not the process listening on port 8080."


def test_built_server_behavior():
    exercise_server(BINARY)


def test_source_compiles_and_behaves():
    rebuilt = "/tmp/sec_api_rebuilt_server"
    result = subprocess.run(
        ["g++", "-std=c++17", "-I" + os.path.join(BASE, "include"), os.path.join(BASE, "src/api_server.cpp"), "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert result.returncode == 0, "Patched source did not compile with the required options:\n" + result.stdout
    exercise_server(rebuilt)


def test_response_log():
    log_file = os.path.join(BASE, "response.log")
    assert os.path.isfile(log_file), f"Response log {log_file} is missing."
    with open(log_file) as f:
        content = f.read().strip()
    expected_response = "Payload valid and correct"
    assert content == expected_response, f"Response log content is incorrect. Expected '{expected_response}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
