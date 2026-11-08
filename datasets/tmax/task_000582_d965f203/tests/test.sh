#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import socket
import subprocess
import time
import urllib.error
import urllib.request
import pytest

SERVER_C = "/home/user/app/server.c"
SERVER_BIN = "/home/user/app/server"
NGINX_CONF = "/home/user/nginx/nginx.conf"
SETUP_SH = "/home/user/setup.sh"
RUN_DIR = "/home/user/run"
SOCKET_PATH = "/home/user/run/app.sock"
SUCCESS_LOG = "/home/user/success.log"


def process_info():
    result = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            exe = os.readlink(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            result[pid] = (exe, cmdline)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def stop_task_services():
    for sig in (15, 9):
        for pid, (exe, cmdline) in process_info().items():
            is_backend = exe == SERVER_BIN or exe.startswith(SERVER_BIN + " (deleted)")
            is_nginx = os.path.basename(exe) == "nginx" and NGINX_CONF in cmdline
            if is_backend or is_nginx:
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        time.sleep(0.4)


def unix_socket_inodes(path):
    inodes = set()
    with open("/proc/net/unix", "r") as f:
        next(f, None)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[7] == path:
                inodes.add(fields[6])
    return inodes


def pids_holding_inodes(inodes):
    holders = set()
    if not inodes:
        return holders
    targets = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in targets:
                        holders.add(int(entry))
                        break
                except (FileNotFoundError, PermissionError):
                    pass
        except (FileNotFoundError, PermissionError):
            pass
    return holders


def tcp_8080_inodes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if local.rsplit(":", 1)[-1].upper() == "1F90" and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def direct_backend_body():
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    client.connect(SOCKET_PATH)
    client.sendall(b"GET /api HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
    chunks = []
    while True:
        data = client.recv(4096)
        if not data:
            break
        chunks.append(data)
    client.close()
    response = b"".join(chunks)
    assert b"\r\n\r\n" in response, "backend did not return a valid HTTP response"
    headers, body = response.split(b"\r\n\r\n", 1)
    assert headers.startswith(b"HTTP/1.1 200") or headers.startswith(b"HTTP/1.0 200")
    return body


def nginx_body():
    with urllib.request.urlopen("http://127.0.0.1:8080/api", timeout=4) as response:
        assert response.status == 200
        return response.read()


def assert_live_stack():
    assert os.path.isdir(RUN_DIR)
    assert stat.S_IMODE(os.stat(RUN_DIR).st_mode) == 0o700
    assert os.path.exists(SOCKET_PATH), "backend socket was not created"
    assert stat.S_ISSOCK(os.stat(SOCKET_PATH).st_mode), f"{SOCKET_PATH} is not a Unix socket"

    info = process_info()
    backend_pids = pids_holding_inodes(unix_socket_inodes(SOCKET_PATH))
    assert backend_pids, "no process is listening on the required Unix socket"
    assert any(info.get(pid, ("", ""))[0] == SERVER_BIN for pid in backend_pids), \
        "the compiled /home/user/app/server is not serving the Unix socket"

    nginx_pids = pids_holding_inodes(tcp_8080_inodes())
    assert nginx_pids, "nothing is listening on TCP port 8080"
    assert any(os.path.basename(info.get(pid, ("", ""))[0]) == "nginx" for pid in nginx_pids), \
        "port 8080 is not served by nginx"
    assert any(os.path.basename(exe) == "nginx" and NGINX_CONF in cmd
               for exe, cmd in info.values()), "nginx was not started with the provided configuration"

    assert direct_backend_body() == b"Hello Microservice"
    assert nginx_body() == b"Hello Microservice"
    return backend_pids, nginx_pids


def run_setup():
    result = subprocess.run([SETUP_SH], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, \
        f"{SETUP_SH} failed to execute properly. stdout: {result.stdout}\nstderr: {result.stderr}"


@pytest.fixture(scope="session")
def completed_setup():
    assert os.path.isfile(SETUP_SH), f"{SETUP_SH} is missing"
    assert os.access(SETUP_SH, os.X_OK), f"{SETUP_SH} is not executable"

    stop_task_services()
    for path in (SERVER_BIN, SOCKET_PATH, SUCCESS_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build_started = time.time_ns()
    run_setup()
    assert os.path.isfile(SERVER_BIN), "setup.sh did not compile the server binary"
    with open(SERVER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "compiled server is not an ELF executable"
    assert os.stat(SERVER_BIN).st_mtime_ns >= build_started, "server binary was not rebuilt by setup.sh"
    first_backend, first_nginx = assert_live_stack()

    # Prove that /api is actually dependent on the C backend rather than being
    # a static nginx response or a forged success.log.
    for pid in first_backend:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    try:
        body_without_backend = nginx_body()
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, ConnectionError):
        body_without_backend = None
    assert body_without_backend != b"Hello Microservice", \
        "nginx returned the target body even after the backend was stopped"

    with open(SUCCESS_LOG, "w") as f:
        f.write("poisoned")
    run_setup()
    second_backend, second_nginx = assert_live_stack()
    assert first_backend.isdisjoint(second_backend), "setup.sh did not restart the previous backend"
    assert first_nginx.isdisjoint(second_nginx), "setup.sh did not restart the previous nginx instance"
    return True


def test_server_c_fixed():
    assert os.path.isfile(SERVER_C), f"{SERVER_C} is missing"
    with open(SERVER_C, "r") as f:
        content = f.read()
    assert "/home/user/run/app.sock" in content, \
        f"{SERVER_C} does not contain the correct socket path '/home/user/run/app.sock'"
    assert "/tmp/wrong.sock" not in content, f"{SERVER_C} still contains the old wrong socket path"


def test_nginx_conf_fixed():
    assert os.path.isfile(NGINX_CONF), f"{NGINX_CONF} is missing"
    with open(NGINX_CONF, "r") as f:
        content = f.read()
    assert "/home/user/run/app.sock" in content, \
        f"{NGINX_CONF} does not contain the correct socket path '/home/user/run/app.sock'"
    result = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF, "-p", "/home/user/nginx"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"nginx configuration is invalid: {result.stderr}"


def test_run_dir_permissions(completed_setup):
    assert os.path.isdir(RUN_DIR), f"{RUN_DIR} directory is missing"
    permissions = stat.S_IMODE(os.stat(RUN_DIR).st_mode)
    assert permissions == 0o700, f"{RUN_DIR} permissions are {oct(permissions)}, expected 0o700"


def test_setup_sh_exists_and_executable():
    assert os.path.isfile(SETUP_SH), f"{SETUP_SH} is missing"
    assert os.access(SETUP_SH, os.X_OK), f"{SETUP_SH} is not executable"


def test_setup_sh_idempotent_execution(completed_setup):
    assert completed_setup


def test_success_log_content(completed_setup):
    assert os.path.isfile(SUCCESS_LOG), f"{SUCCESS_LOG} is missing"
    with open(SUCCESS_LOG, "r") as f:
        content = f.read()
    assert content.strip() == "Hello Microservice", \
        f"{SUCCESS_LOG} contains '{content.strip()}', expected exactly 'Hello Microservice'"
    assert content == "Hello Microservice", \
        f"{SUCCESS_LOG} must contain only the response body with no extra content"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
