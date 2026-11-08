#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tarfile
import tempfile
import time
import pytest

ROOT = "/home/user/migration"
SOURCE = ROOT + "/src/server.c"
BINARY = ROOT + "/bin/backend_daemon"
PID_FILE = ROOT + "/daemon.pid"
SOCKET = ROOT + "/socket/backend.sock"
LOG = ROOT + "/logs/app.log"

ORIGINAL_SOURCE = b'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main() {
    int server_fd, client_fd;
    struct sockaddr_un address;
    // Bug to be fixed by agent
    char *socket_path = "/home/user/migration/wrong.sock";

    unlink(socket_path);

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    memset(&address, 0, sizeof(struct sockaddr_un));
    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, socket_path, sizeof(address.sun_path) - 1);

    bind(server_fd, (struct sockaddr *)&address, sizeof(struct sockaddr_un));
    listen(server_fd, 5);

    FILE *f = fopen("/home/user/migration/logs/app.log", "a");
    if(f) { fprintf(f, "Server started\\n"); fflush(f); }

    while(1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd > 0) {
            char buffer[1024];
            read(client_fd, buffer, sizeof(buffer));
            char *response = "HTTP/1.1 200 OK\\r\\nContent-Length: 13\\r\\n\\r\\nHello Server!";
            write(client_fd, response, strlen(response));
            if(f) { fprintf(f, "Request served\\n"); fflush(f); }
            close(client_fd);
        }
    }
    return 0;
}
'''


def read_pid():
    assert os.path.isfile(PID_FILE), f"PID file missing: {PID_FILE}"
    with open(PID_FILE) as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    return int(pid_str)


def test_backup_exists_and_valid():
    backup_path = ROOT + "/backup/src_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup file missing: {backup_path}"

    with tarfile.open(backup_path, "r:gz") as tar:
        names = [os.path.basename(m.name) for m in tar.getmembers()]
        assert "server.c" in names, "server.c not found in the backup tarball"
        members = [m for m in tar.getmembers()
                   if os.path.basename(m.name) == "server.c" and m.isfile()]
        assert members, "Backup does not contain a regular server.c file"
        assert tar.extractfile(members[0]).read() == ORIGINAL_SOURCE, \
            "Backup server.c is not the original pre-modification source"


def test_source_was_fixed_and_compiles():
    assert os.path.isfile(SOURCE), f"Source file missing: {SOURCE}"
    with open(SOURCE, "rb") as f:
        source = f.read()
    assert source != ORIGINAL_SOURCE, "server.c was not modified"
    assert b'/home/user/migration/socket/backend.sock' in source, \
        "server.c does not contain the required socket path"

    with tempfile.TemporaryDirectory() as td:
        result = subprocess.run(
            ["gcc", SOURCE, "-o", os.path.join(td, "backend_daemon")],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        assert result.returncode == 0, \
            "Updated server.c does not compile:\n" + result.stderr.decode(errors="replace")


def test_binary_and_process():
    assert os.path.isfile(BINARY), f"Compiled binary missing: {BINARY}"
    mode = os.stat(BINARY).st_mode
    assert mode & 0o111, f"Compiled binary is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        binary_data = f.read()
    assert binary_data.startswith(b"\x7fELF"), "backend_daemon is not a compiled ELF executable"
    assert b'/home/user/migration/socket/backend.sock' in binary_data, \
        "Compiled binary does not contain the configured socket path"

    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running")

    proc_exe = f"/proc/{pid}/exe"
    assert os.path.exists(proc_exe), f"PID {pid} has no running executable"
    assert os.path.samefile(proc_exe, BINARY), \
        f"PID {pid} is not running {BINARY}"


def test_socket_exists_and_is_owned_by_daemon():
    assert os.path.exists(SOCKET), f"Socket missing: {SOCKET}"
    mode = os.stat(SOCKET).st_mode
    assert stat.S_ISSOCK(mode), f"{SOCKET} is not a socket"

    socket_inode = None
    with open("/proc/net/unix") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 8 and parts[7] == SOCKET:
                socket_inode = parts[6]
                break
    assert socket_inode is not None, f"No active UNIX socket is bound at {SOCKET}"

    pid = read_pid()
    fd_dir = f"/proc/{pid}/fd"
    owned = False
    for fd in os.listdir(fd_dir):
        try:
            if os.readlink(os.path.join(fd_dir, fd)) == f"socket:[{socket_inode}]":
                owned = True
                break
        except OSError:
            pass
    assert owned, f"PID {pid} does not own the socket bound at {SOCKET}"


def test_proxy_response_and_request_logging():
    response_file = ROOT + "/test_response.txt"
    assert os.path.isfile(response_file), f"Response file missing: {response_file}"
    with open(response_file, "rb") as f:
        saved_response = f.read()
    assert b"Hello Server!" in saved_response, \
        "Response file does not contain 'Hello Server!'"

    before = os.path.getsize(LOG) if os.path.exists(LOG) else 0
    result = subprocess.run(
        ["curl", "-s", "--max-time", "5", "--unix-socket", SOCKET,
         "http://localhost/"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, \
        "Live curl request failed: " + result.stderr.decode(errors="replace")
    assert result.stdout == saved_response, \
        "test_response.txt is not the exact response body returned by the daemon"
    assert result.stdout == b"Hello Server!", "Daemon returned an unexpected response body"

    for _ in range(20):
        if os.path.exists(LOG) and os.path.getsize(LOG) > before:
            break
        time.sleep(0.05)
    assert os.path.exists(LOG) and os.path.getsize(LOG) > before, \
        "Daemon did not append to app.log when handling the live request"


def test_monitoring_script_and_status():
    monitor_script = ROOT + "/monitor.sh"
    status_file = ROOT + "/status.txt"
    assert os.path.isfile(monitor_script), f"Monitor script missing: {monitor_script}"
    assert os.path.isfile(status_file), f"Status file missing: {status_file}"
    with open(status_file) as f:
        status_content = f.read()
    assert "Log Active" in status_content, "Status file does not contain 'Log Active'"

    # Exercise the submitted monitor rather than trusting the pre-created status file.
    open(LOG, "wb").close()
    if os.path.exists(status_file):
        os.unlink(status_file)
    empty_run = subprocess.run(["bash", monitor_script], stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=10)
    assert empty_run.returncode == 0, \
        "monitor.sh failed on an empty log: " + empty_run.stderr.decode(errors="replace")
    if os.path.exists(status_file):
        with open(status_file) as f:
            assert "Log Active" not in f.read(), \
                "monitor.sh reported Log Active for an empty log"

    with open(LOG, "wb") as f:
        f.write(b"verification log entry\n")
    active_run = subprocess.run(["bash", monitor_script], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=10)
    assert active_run.returncode == 0, \
        "monitor.sh failed on a non-empty log: " + active_run.stderr.decode(errors="replace")
    assert os.path.isfile(status_file), "monitor.sh did not create status.txt"
    with open(status_file) as f:
        assert f.read().strip() == "Log Active", \
            "monitor.sh did not write the required status for a non-empty log"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
