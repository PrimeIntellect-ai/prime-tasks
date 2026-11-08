#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import tempfile
import time
import uuid
import pytest

APP = "/home/user/app"
SERVER = os.path.join(APP, "server")
CLIENT = os.path.join(APP, "client")
SOCKET = os.path.join(APP, "grpc.sock")
LOG = "/home/user/test_results.log"
EXPECTED_RAW = (
    "Req 1: OK\n"
    "Req 2: OK\n"
    "Req 3: OK\n"
    "Req 4: RATE_LIMITED\n"
    "Req 5: RATE_LIMITED\n"
)

EXPECTED_SOURCES = {
    "libvalidator.cpp": '''#include <string>
#include <unordered_map>

std::unordered_map<std::string, int> request_counts;

bool validate_request(std::string user_id) {
    if (request_counts[user_id] >= 3) {
        return false;
    }
    request_counts[user_id]++;
    return true;
}
''',
    "server.cpp": '''// server.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstring>

extern bool validate_request(std::string user_id);

int main() {
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, "/home/user/app/grpc.sock");
    unlink("/home/user/app/grpc.sock");
    bind(server_fd, (struct sockaddr*)&addr, sizeof(addr));
    listen(server_fd, 5);

    while (true) {
        int client_fd = accept(server_fd, NULL, NULL);
        char buffer[256] = {0};
        read(client_fd, buffer, 255);
        std::string user_id(buffer);

        bool ok = validate_request(user_id);
        std::string reply = ok ? "OK" : "RATE_LIMITED";
        write(client_fd, reply.c_str(), reply.length());
        close(client_fd);
    }
    return 0;
}
''',
    "client.cpp": '''#include <iostream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstring>

void send_req(int i) {
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, "/home/user/app/grpc.sock");
    connect(sock, (struct sockaddr*)&addr, sizeof(addr));
    std::string msg = "test_user";
    write(sock, msg.c_str(), msg.length());
    char buffer[256] = {0};
    read(sock, buffer, 255);
    std::cout << "Req " << i << ": " << buffer << std::endl;
    close(sock);
}

int main() {
    for(int i=1; i<=5; i++) {
        send_req(i);
    }
    return 0;
}
'''
}


def kill_existing_servers():
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            exe = os.readlink(f"/proc/{entry}/exe")
            if exe == SERVER or exe == SERVER + " (deleted)":
                os.kill(int(entry), signal.SIGKILL)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass


def assert_sources_unchanged():
    for name, expected in EXPECTED_SOURCES.items():
        path = os.path.join(APP, name)
        assert os.path.isfile(path), f"{name} is missing."
        with open(path, "r") as f:
            actual = f.read()
        assert actual == expected, f"{name} was modified; only the Makefile may be changed."


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF executable."


def dynamic_info():
    return subprocess.check_output(
        ["readelf", "-d", SERVER], stderr=subprocess.STDOUT, text=True
    )


def send_request(user):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(2)
    try:
        sock.connect(SOCKET)
        sock.sendall(user.encode())
        return sock.recv(256).decode()
    finally:
        sock.close()


def test_executables_built():
    assert os.path.isfile(SERVER), "The server executable was not built."
    assert os.path.isfile(CLIENT), "The client executable was not built."
    assert os.access(SERVER, os.X_OK), "The server file is not executable."
    assert os.access(CLIENT, os.X_OK), "The client file is not executable."


def test_test_results_log_exists():
    assert os.path.isfile(LOG), "The /home/user/test_results.log file is missing."


def test_test_results_log_content():
    expected_content = [
        "Req 1: OK",
        "Req 2: OK",
        "Req 3: OK",
        "Req 4: RATE_LIMITED",
        "Req 5: RATE_LIMITED"
    ]
    with open(LOG, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) == 5, f"Expected 5 lines in test_results.log, but found {len(lines)}."
    for i, expected in enumerate(expected_content):
        assert lines[i] == expected, f"Line {i+1} in test_results.log is incorrect. Expected '{expected}', got '{lines[i]}'."


def test_server_rpath_configured():
    try:
        output = dynamic_info()
        assert "RUNPATH" in output or "RPATH" in output, "The server executable does not have RPATH/RUNPATH configured."
        assert "/home/user/app" in output, "The server executable RPATH/RUNPATH does not point to /home/user/app."
    except FileNotFoundError:
        pass


def test_only_allowed_sources_remain_and_validator_is_original():
    assert_sources_unchanged()
    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "libvalidator.cpp")
        library = os.path.join(td, "libvalidator.so")
        with open(source, "w") as f:
            f.write(EXPECTED_SOURCES["libvalidator.cpp"])
        subprocess.run([
            "g++", "-fPIC", "-shared", "-D_GLIBCXX_USE_CXX11_ABI=0",
            source, "-o", library
        ], check=True)
        with open(library, "rb") as f:
            expected_library = f.read()
        with open(os.path.join(APP, "libvalidator.so"), "rb") as f:
            actual_library = f.read()
        assert actual_library == expected_library, "libvalidator.so was modified; only the Makefile may be changed."


def test_makefile_rebuild_and_linkage():
    kill_existing_servers()
    subprocess.run(["make", "clean"], cwd=APP, check=True, timeout=30)
    subprocess.run(["make"], cwd=APP, check=True, timeout=60)
    assert_sources_unchanged()

    for path in (SERVER, CLIENT):
        assert os.path.isfile(path) and os.access(path, os.X_OK)
        assert_elf(path)

    dry_run = subprocess.check_output(["make", "-Bn", "all"], cwd=APP, text=True)
    assert "server.cpp" in dry_run, "The Makefile does not build server from server.cpp."
    assert "client.cpp" in dry_run, "The Makefile does not build client from client.cpp."
    assert "_GLIBCXX_USE_CXX11_ABI=0" in dry_run, "The server compile command does not select the old C++11 ABI."
    assert re.search(r"rpath", dry_run, re.IGNORECASE) and "/home/user/app" in dry_run, "The Makefile does not set the required rpath."

    info = dynamic_info()
    assert "libvalidator.so" in info, "The server is not dynamically linked to libvalidator.so."
    assert ("RUNPATH" in info or "RPATH" in info) and "/home/user/app" in info

    symbols = subprocess.check_output(["nm", "-D", SERVER], text=True)
    assert re.search(r"\bU\s+_Z16validate_requestSs\b", symbols), "The server does not reference the old-ABI validate_request(std::string) symbol."


def test_real_server_client_and_rate_limiting_behavior():
    kill_existing_servers()
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    proc = subprocess.Popen(
        [SERVER], cwd=APP, env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(SOCKET) and proc.poll() is None:
            time.sleep(0.05)
        assert proc.poll() is None, "The rebuilt server failed to start using its configured rpath."
        assert os.path.exists(SOCKET), "The server did not create its Unix socket."

        client_run = subprocess.run(
            [CLIENT], cwd=APP, capture_output=True, text=True, timeout=10, check=True
        )
        assert client_run.stderr == "", "The client emitted unexpected standard error."
        assert client_run.stdout == EXPECTED_RAW, "The actual client/server output is incorrect."
        with open(LOG, "r") as f:
            recorded = f.read()
        assert recorded == client_run.stdout, "test_results.log is not the exact stdout produced by the working client."

        user_a = "verify_a_" + uuid.uuid4().hex
        user_b = "verify_b_" + uuid.uuid4().hex
        sequence = [user_a, user_a, user_b, user_a, user_a, user_b, user_b, user_b]
        expected = ["OK", "OK", "OK", "OK", "RATE_LIMITED", "OK", "OK", "RATE_LIMITED"]
        actual = [send_request(user) for user in sequence]
        assert actual == expected, f"Live per-user rate limiting is incorrect: {actual}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        try:
            os.unlink(SOCKET)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
