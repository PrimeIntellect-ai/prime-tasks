#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import stat
import subprocess
import tempfile
import time
import pytest

SOURCE = "/home/user/backend.c"
BACKEND = "/home/user/backend"
SUPERVISOR = "/home/user/supervisor.sh"
SOCK = "/home/user/run/backend.sock"
LOG = "/home/user/backend.log"

EXPECTED_SOURCE = '''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCKET_PATH "/home/user/run/backend.sock"

int main() {
    int server_fd, client_fd;
    struct sockaddr_un addr;
    char buffer[1024] = {0};

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);
    unlink(SOCKET_PATH);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        perror("bind failed");
        exit(1);
    }

    listen(server_fd, 5);
    printf("Backend listening on %s...\\n", SOCKET_PATH);
    fflush(stdout);

    while (1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd >= 0) {
            int valread = read(client_fd, buffer, 1024);
            if(valread > 0) {
                send(client_fd, "ACK\\n", 4, 0);
            }
            close(client_fd);
        }
    }
    return 0;
}
'''

supervisor_proc = None


def wait_until(predicate, timeout=8.0, interval=0.05):
    end = time.time() + timeout
    while time.time() < end:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return None


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return None


def direct_backend_child(parent_pid):
    try:
        pids = [int(x) for x in os.listdir("/proc") if x.isdigit()]
    except OSError:
        return None
    for pid in pids:
        try:
            with open(f"/proc/{pid}/status") as f:
                fields = dict(line.split(":", 1) for line in f if ":" in line)
            if int(fields["PPid"].strip()) == parent_pid and proc_exe(pid) == BACKEND:
                return pid
        except (OSError, KeyError, ValueError):
            pass
    return None


def stop_old_deployment():
    me = os.getpid()
    victims = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        if pid == me:
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="ignore")
            if SUPERVISOR in cmdline or proc_exe(pid) == BACKEND:
                victims.append(pid)
        except OSError:
            pass
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in victims:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.3)


def request_ack(timeout=2.0):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    try:
        client.connect(SOCK)
        client.sendall(b"PING")
        return client.recv(1024).decode("utf-8")
    finally:
        client.close()


def socket_is_owned_by(pid):
    kernel_inode = None
    try:
        with open("/proc/net/unix") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 8 and parts[-1] == SOCK:
                    kernel_inode = parts[6]
    except OSError:
        return False
    if kernel_inode is None:
        return False
    wanted = f"socket:[{kernel_inode}]"
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                if os.readlink(f"/proc/{pid}/fd/{fd}") == wanted:
                    return True
            except OSError:
                pass
    except OSError:
        return False
    return False


def fd_targets_log(pid):
    try:
        return (os.path.realpath(f"/proc/{pid}/fd/1") == LOG and
                os.path.realpath(f"/proc/{pid}/fd/2") == LOG)
    except OSError:
        return False


def test_run_dir_permissions():
    dir_path = "/home/user/run"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."
    mode = stat.S_IMODE(os.stat(dir_path).st_mode)
    assert mode == 0o700, f"Permissions for {dir_path} should be 700, but are {oct(mode)}."


def test_backend_c_updated():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "/home/user/run/backend.sock" in content, "backend.c does not contain the updated socket path."
    assert content == EXPECTED_SOURCE, "backend.c was changed beyond the required socket-path replacement."


def test_backend_executable():
    assert os.path.isfile(BACKEND), f"Executable {BACKEND} is missing."
    assert os.access(BACKEND, os.X_OK), f"File {BACKEND} is not executable."
    with open(BACKEND, "rb") as f:
        assert f.read(4) == b"\x7fELF", "backend is not a compiled ELF executable."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "backend")
        subprocess.run(["gcc", SOURCE, "-o", rebuilt], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with open(BACKEND, "rb") as submitted, open(rebuilt, "rb") as expected:
            assert submitted.read() == expected.read(), \
                "backend is not the gcc output of the required backend.c source."


def test_response_file():
    file_path = "/home/user/response.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read().strip()
    assert "ACK" in content, f"response.txt does not contain 'ACK'. Found: {content}"


def test_supervisor_running_and_restarts_backend():
    global supervisor_proc
    assert os.path.isfile(SUPERVISOR), f"Script {SUPERVISOR} is missing."
    assert os.access(SUPERVISOR, os.X_OK), f"Script {SUPERVISOR} is not executable."

    stop_old_deployment()
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    with open(LOG, "w"):
        pass

    supervisor_proc = subprocess.Popen(
        [SUPERVISOR], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True)

    first_pid = wait_until(lambda: direct_backend_child(supervisor_proc.pid))
    assert supervisor_proc.poll() is None, "supervisor.sh process is not running."
    assert first_pid, "supervisor.sh did not run /home/user/backend in the foreground."
    assert wait_until(lambda: os.path.exists(SOCK)), "Backend socket was not created."
    assert stat.S_ISSOCK(os.stat(SOCK).st_mode), f"{SOCK} is not a UNIX socket."
    assert wait_until(lambda: socket_is_owned_by(first_pid)), \
        "The supervised backend process does not own backend.sock."
    assert fd_targets_log(first_pid), \
        "Backend stdout and stderr are not both redirected to backend.log."
    assert "ACK" in request_ack(), "Expected 'ACK' from the supervised backend."

    os.kill(first_pid, signal.SIGKILL)
    second_pid = wait_until(
        lambda: (p if (p := direct_backend_child(supervisor_proc.pid)) != first_pid else None),
        timeout=8.0)
    assert supervisor_proc.poll() is None, "supervisor.sh exited after the backend crashed."
    assert second_pid and second_pid != first_pid, "supervisor.sh did not restart the backend."
    assert wait_until(lambda: socket_is_owned_by(second_pid)), \
        "Restarted backend does not own backend.sock."
    assert fd_targets_log(second_pid), \
        "Restarted backend stdout and stderr are not redirected to backend.log."
    assert "ACK" in request_ack(), "Restarted backend did not return ACK."

    with open(LOG, "r", errors="replace") as f:
        log_content = f.read()
    assert "Backend listening on /home/user/run/backend.sock" in log_content, \
        "backend.log does not contain output from the backend."


def test_socket_live():
    assert os.path.exists(SOCK), f"Socket {SOCK} does not exist."
    try:
        response = request_ack()
        assert "ACK" in response, f"Expected 'ACK' from socket, got {response}"
    except Exception as e:
        pytest.fail(f"Failed to communicate with socket {SOCK}: {e}")
TEST_EOF

if timeout 45s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
