#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import socket
import subprocess
import time
import pytest

SOURCE = "/home/user/account_daemon.c"
BINARY = "/home/user/account_daemon"
SCRIPT = "/home/user/add_user.exp"
LOG = "/home/user/result.log"
DAEMON = None

EXPECTED_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");

    address.sin_port = htons(8888);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            continue;
        }

        char *welcome = "Welcome to AccountMgr. Enter command (ADD/DEL/QUIT): ";
        send(new_socket, welcome, strlen(welcome), 0);

        int valread = read(new_socket, buffer, 1024);
        if (strncmp(buffer, "ADD", 3) == 0) {
            char *prompt = "Username: ";
            send(new_socket, prompt, strlen(prompt), 0);
            memset(buffer, 0, sizeof(buffer));
            read(new_socket, buffer, 1024);
            char *success = "Success. Account created.\n";
            send(new_socket, success, strlen(success), 0);
        }
        close(new_socket);
    }
    return 0;
}
'''

def normalized_c(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return re.sub(r'\s+', '', text)

def stop_existing_listener():
    result = subprocess.run(["ss", "-H", "-ltnp"], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    pids = set()
    for line in result.stdout.splitlines():
        if re.search(r'(?:127\.0\.0\.1|0\.0\.0\.0|\[::\]|\*)?:8888\b', line):
            pids.update(int(x) for x in re.findall(r'pid=(\d+)', line))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

def wait_for_daemon(proc):
    deadline = time.time() + 4
    while time.time() < deadline:
        assert proc.poll() is None, "Compiled account_daemon exited before listening"
        try:
            with socket.create_connection(("127.0.0.1", 8888), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("Connection refused: account_daemon did not listen on 127.0.0.1:8888")

def recv_until(sock, expected):
    data = b""
    deadline = time.time() + 2
    while expected not in data and time.time() < deadline:
        chunk = sock.recv(1024)
        if not chunk:
            break
        data += chunk
    return data

def interact(username):
    with socket.create_connection(("127.0.0.1", 8888), timeout=2) as s:
        s.settimeout(2)
        welcome = recv_until(s, b"Enter command")
        assert b"Welcome to AccountMgr. Enter command (ADD/DEL/QUIT):" in welcome, \
            "Daemon did not send the expected welcome message."
        s.sendall(b"ADD\n")
        prompt = recv_until(s, b"Username:")
        assert b"Username:" in prompt, "Daemon did not prompt for Username."
        s.sendall(username.encode() + b"\n")
        response = recv_until(s, b"Success. Account created.")
        assert b"Success. Account created." in response, \
            "Daemon did not send success message."

def test_c_code_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    content = open(SOURCE).read()
    assert "htons" in content and "8888" in content, \
        "The C code does not appear to be fixed with htons(8888)."
    assert re.search(r'address\s*\.\s*sin_port\s*=\s*htons\s*\(\s*8888\s*\)\s*;', content), \
        "sin_port is not assigned htons(8888)."
    assert normalized_c(content) == normalized_c(EXPECTED_SOURCE), \
        "The C program was changed beyond the required network byte-order fix."

def test_compiled_binary_is_from_source_and_running():
    global DAEMON
    assert os.path.isfile(BINARY), f"Compiled daemon {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Compiled daemon {BINARY} is not executable."

    rebuilt = "/tmp/account_daemon.rebuilt"
    subprocess.run(["gcc", SOURCE, "-o", rebuilt], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with open(BINARY, "rb") as submitted, open(rebuilt, "rb") as expected:
        assert submitted.read() == expected.read(), \
            "account_daemon is not the gcc-compiled form of account_daemon.c."

    stop_existing_listener()
    DAEMON = subprocess.Popen([BINARY], stdin=subprocess.DEVNULL,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                              start_new_session=True)
    wait_for_daemon(DAEMON)
    assert os.path.samefile(f"/proc/{DAEMON.pid}/exe", BINARY), \
        "The process listening for the test is not /home/user/account_daemon."

def test_daemon_listening_and_responding():
    interact("admin_xyz")
    # Exercise another verifier-derived username rather than trusting one fixed transcript.
    interact("verify_" + secrets.token_hex(8))

def test_expect_script_exists_and_valid():
    assert os.path.isfile(SCRIPT), f"Expect script {SCRIPT} is missing."
    content = open(SCRIPT).read()
    assert "spawn" in content, "The file does not appear to be a valid Expect script (missing 'spawn')."
    assert "nc" in content and "127.0.0.1" in content and "8888" in content, \
        "The Expect script does not appear to spawn 'nc 127.0.0.1 8888'."
    assert "expect" in content and "send" in content, \
        "The Expect script is missing 'expect' or 'send' commands."
    assert "ADD" in content and "admin_xyz" in content, \
        "The Expect script does not perform the required ADD interaction."

    wrapper_dir = "/tmp/verifier-path"
    marker = "/tmp/verifier-nc-invocation"
    os.makedirs(wrapper_dir, exist_ok=True)
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass
    wrapper = os.path.join(wrapper_dir, "nc")
    with open(wrapper, "w") as f:
        f.write('#!/bin/sh\nprintf "%s\\n" "$*" >> /tmp/verifier-nc-invocation\nexec /usr/bin/nc "$@"\n')
    os.chmod(wrapper, 0o755)
    try:
        os.unlink(LOG)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["PATH"] = wrapper_dir + ":" + env.get("PATH", "")
    with open(LOG, "wb") as output:
        completed = subprocess.run(["expect", SCRIPT], stdout=output,
                                   stderr=subprocess.PIPE, env=env, timeout=10)
    assert completed.returncode == 0, \
        "The Expect script did not successfully complete and exit cleanly."
    assert os.path.isfile(marker), "The executed Expect script never invoked nc."
    calls = open(marker).read().splitlines()
    assert any(re.fullmatch(r'127\.0\.0\.1\s+8888', call.strip()) for call in calls), \
        "The executed Expect script did not invoke nc 127.0.0.1 8888."

def test_result_log_content():
    assert os.path.isfile(LOG), f"Log file {LOG} is missing."
    content = open(LOG).read()
    assert "Success. Account created." in content, \
        f"The log file {LOG} does not contain the expected success message."
    assert "Welcome to AccountMgr. Enter command (ADD/DEL/QUIT):" in content
    assert "Username:" in content
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
