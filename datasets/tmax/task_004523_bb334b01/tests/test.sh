#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import socket
import subprocess
import time

import pytest

HOST = "127.0.0.1"
PORT = 8050
BINARY = "/home/user/search_server"
SOURCE = "/home/user/search_server.c"
ARCHIVE = "/app/archive"
KEY = b"sunflower"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    if not inodes:
        return owners
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def stop_existing_listener():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids(PORT)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.time() + 2
        while time.time() < deadline and listener_pids(PORT):
            time.sleep(0.05)
    assert not listener_pids(PORT), f"Could not stop existing listener on port {PORT}"


def send_query_and_get_response(query: str) -> str:
    try:
        with socket.create_connection((HOST, PORT), timeout=2.0) as s:
            s.sendall(query.encode("utf-8"))
            response = s.recv(1024).decode("utf-8")
            return response
    except ConnectionRefusedError:
        pytest.fail(f"Connection refused to {HOST}:{PORT}. Is the server running?")
    except socket.timeout:
        pytest.fail(f"Connection to {HOST}:{PORT} timed out waiting for a response.")
    except Exception as e:
        pytest.fail(f"Unexpected error communicating with server: {e}")


def encrypt_csv(text: str) -> bytes:
    raw = text.encode("utf-8")
    return bytes(byte ^ KEY[i % len(KEY)] for i, byte in enumerate(raw))


@pytest.fixture(scope="session", autouse=True)
def run_submitted_server():
    assert os.path.exists(SOURCE), "The C source code /home/user/search_server.c is missing."
    assert os.path.exists(BINARY), "The compiled binary /home/user/search_server is missing."
    assert os.access(BINARY, os.X_OK), "The binary /home/user/search_server is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted search_server is not a compiled ELF executable."

    stop_existing_listener()
    proc = subprocess.Popen([BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 5
    owners = set()
    while time.time() < deadline:
        owners = listener_pids(PORT)
        if owners:
            break
        if proc.poll() is not None:
            pytest.fail(f"The submitted executable exited with status {proc.returncode} before listening.")
        time.sleep(0.05)
    assert owners, f"The submitted executable did not listen on {HOST}:{PORT}."

    matching_owner = False
    for pid in owners:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", BINARY):
                matching_owner = True
                break
        except (FileNotFoundError, OSError):
            pass
    assert matching_owner, "The service listening on port 8050 is not the submitted compiled executable."

    yield

    for pid in listener_pids(PORT):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()


def test_server_source_and_binary_exist():
    assert os.path.exists("/home/user/search_server.c"), "The C source code /home/user/search_server.c is missing."
    assert os.path.exists("/home/user/search_server"), "The compiled binary /home/user/search_server is missing."
    assert os.access("/home/user/search_server", os.X_OK), "The binary /home/user/search_server is not executable."


def test_query_omega_backup():
    response = send_query_and_get_response("omega_backup\n")
    assert response == "MATCH: fileB.zdat\n", f"Expected 'MATCH: fileB.zdat\\n' but got {repr(response)}"


def test_query_alpha_core():
    response = send_query_and_get_response("alpha_core\n")
    assert response == "MATCH: fileA.zdat\n", f"Expected 'MATCH: fileA.zdat\\n' but got {repr(response)}"


def test_query_zeta_frontend():
    response = send_query_and_get_response("zeta_frontend\n")
    assert response == "MATCH: fileC.zdat\n", f"Expected 'MATCH: fileC.zdat\\n' but got {repr(response)}"


def test_query_nonexistent_proj():
    response = send_query_and_get_response("nonexistent_proj\n")
    assert response == "NONE\n", f"Expected 'NONE\\n' but got {repr(response)}"


def test_random_runtime_archive_entries_are_decoded_and_rescanned():
    token = secrets.token_hex(12)
    filename = f"runtime_{secrets.token_hex(8)}.zdat"
    path = os.path.join(ARCHIVE, filename)
    first_project = f"project_{token}_first"
    second_project = f"project_{token}_second"
    absent_project = f"project_{secrets.token_hex(12)}_absent"

    try:
        with open(path, "wb") as f:
            f.write(encrypt_csv(f"{first_project},v7.3,{token}\n"))

        assert send_query_and_get_response(first_project + "\n") == f"MATCH: {filename}\n"
        assert send_query_and_get_response(absent_project + "\n") == "NONE\n"

        with open(path, "wb") as f:
            f.write(encrypt_csv(f"{second_project},v9.8,{token}\n"))

        assert send_query_and_get_response(first_project + "\n") == "NONE\n"
        assert send_query_and_get_response(second_project + "\n") == f"MATCH: {filename}\n"
    finally:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
