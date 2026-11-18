#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import socket
import stat
import subprocess
import tarfile
import time
from pathlib import Path

BACKUP = "/home/user/backup/pre_hardening.tar.gz"
CONFIG = "/home/user/nginx/nginx.conf"
SOURCE = "/home/user/backend/server.c"
SERVER = "/home/user/backend/server"
SOCKET = "/home/user/backend/secure.sock"
SCRIPT = "/home/user/ci_deploy.sh"
LOG = "/home/user/pipeline_result.log"
PREFIX = "/home/user/nginx/"
EXPECTED_BODY = b'{"status":"secure"}'

ORIGINAL_CONFIG = '''worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/tmp/client_body;
    proxy_temp_path /home/user/nginx/tmp/proxy;
    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location /api/ {
            proxy_pass http://unix:/tmp/missing_backend.sock;
            proxy_set_header Host $host;
        }
    }
}
'''

ORIGINAL_SOURCE = '''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>

#define SOCKET_PATH "/tmp/unsafe_backend.sock"

int main() {
    int server_fd, client_fd;
    struct sockaddr_un address;

    unlink(SOCKET_PATH);

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd == 0) {
        perror("Socket failed");
        exit(EXIT_FAILURE);
    }

    address.sun_family = AF_UNIX;
    strcpy(address.sun_path, SOCKET_PATH);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("Bind failed");
        exit(EXIT_FAILURE);
    }

    // Insecure: no permissions applied here currently

    if (listen(server_fd, 3) < 0) {
        perror("Listen failed");
        exit(EXIT_FAILURE);
    }

    char buffer[1024] = {0};
    char *response = "HTTP/1.1 200 OK\\r\\nContent-Type: application/json\\r\\n\\r\\n{\\"status\\":\\"secure\\"}";

    while(1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            continue;
        }
        read(client_fd, buffer, 1024);
        write(client_fd, response, strlen(response));
        close(client_fd);
    }

    close(server_fd);
    unlink(SOCKET_PATH);
    return 0;
}
'''

EXPECTED_CONFIG = ORIGINAL_CONFIG.replace(
    "proxy_pass http://unix:/tmp/missing_backend.sock;",
    "proxy_pass http://unix:/home/user/backend/secure.sock;",
)


def tar_member_bytes(tar, suffix):
    matches = [m for m in tar.getmembers() if m.isfile() and m.name.endswith(suffix)]
    assert len(matches) == 1, f"Backup must contain exactly one {suffix}"
    f = tar.extractfile(matches[0])
    assert f is not None
    return f.read()


def nginx_account():
    proc = subprocess.run(["nginx", "-V"], stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True)
    match = re.search(r"--user=([^ ]+)", proc.stdout)
    return pwd.getpwnam(match.group(1) if match else "nobody")


def demote_to_nginx_user():
    account = nginx_account()
    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)
    return demote


def wait_for_socket(proc, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Server exited early with status {proc.returncode}")
        if os.path.exists(SOCKET) and stat.S_ISSOCK(os.stat(SOCKET).st_mode):
            return
        time.sleep(0.03)
    raise AssertionError("Server did not create the secure Unix socket")


def stop_process(proc):
    if proc and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def running_server_pids():
    found = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if os.path.realpath(entry / "exe") == SERVER:
                found.append(int(entry.name))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return found


def running_configured_nginx_pids():
    found = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmd = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="ignore")
            if "nginx" in cmd and CONFIG in cmd:
                found.append(int(entry.name))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return found


def stop_configured_nginx():
    pidfile = Path("/home/user/nginx/nginx.pid")
    if pidfile.exists():
        try:
            pid = int(pidfile.read_text().strip())
            os.kill(pid, 3)  # SIGQUIT: graceful nginx shutdown
            deadline = time.time() + 3
            while time.time() < deadline and Path(f"/proc/{pid}").exists():
                time.sleep(0.05)
        except (ValueError, ProcessLookupError, PermissionError):
            pass
    for pid in running_configured_nginx_pids():
        try:
            os.kill(pid, 3)
        except ProcessLookupError:
            pass
    time.sleep(0.15)


def exercise_unix_server(binary):
    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass
    proc = subprocess.Popen([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            preexec_fn=demote_to_nginx_user())
    try:
        wait_for_socket(proc)
        assert stat.S_IMODE(os.stat(SOCKET).st_mode) == 0o600, "Socket permissions are not 0600"
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(2)
        client.connect(SOCKET)
        client.sendall(b"GET /api/status HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        data = b""
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            data += chunk
        client.close()
        assert data.split(b"\r\n\r\n", 1)[-1] == EXPECTED_BODY
    finally:
        stop_process(proc)
        try:
            os.unlink(SOCKET)
        except FileNotFoundError:
            pass


def test_backup_exists_and_valid():
    assert os.path.isfile(BACKUP), f"Backup file {BACKUP} is missing."
    with tarfile.open(BACKUP, "r:gz") as tar:
        names = tar.getnames()
        assert any(name.endswith("backend/server.c") for name in names), "Backup does not contain backend/server.c"
        assert any(name.endswith("nginx/nginx.conf") for name in names), "Backup does not contain nginx/nginx.conf"
        assert any("backend/" in name for name in names), "Backend directory was not archived"
        assert any("nginx/" in name for name in names), "Nginx directory was not archived"
        assert tar_member_bytes(tar, "backend/server.c") == ORIGINAL_SOURCE.encode(), "Backup server.c is not the original file"
        assert tar_member_bytes(tar, "nginx/nginx.conf") == ORIGINAL_CONFIG.encode(), "Backup nginx.conf is not the original file"


def test_nginx_config_hardened_without_other_changes():
    assert os.path.isfile(CONFIG), f"Nginx config {CONFIG} is missing."
    content = Path(CONFIG).read_text()
    assert "proxy_pass http://unix:/home/user/backend/secure.sock;" in content
    assert content == EXPECTED_CONFIG, "Nginx settings other than proxy_pass were changed"
    check = subprocess.run(["nginx", "-t", "-c", CONFIG, "-p", PREFIX],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert check.returncode == 0, check.stdout


def test_c_code_modified_and_secured():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    content = Path(SOURCE).read_text()
    assert "/home/user/backend/secure.sock" in content
    chmod_match = re.search(r"chmod\s*\([^,]+,\s*0?600\s*\)", content)
    assert chmod_match is not None, "C source does not contain chmod(..., 0600)"
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.S)
    bind_pos = code.find("bind(")
    chmod_pos = code.find("chmod(")
    listen_pos = code.find("listen(")
    assert -1 not in (bind_pos, chmod_pos, listen_pos)
    assert bind_pos < chmod_pos < listen_pos, "chmod() must occur after bind() and before listen()"

    compiled = "/tmp/server_compiled_from_submission"
    build = subprocess.run(["gcc", SOURCE, "-o", compiled], stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True)
    assert build.returncode == 0, build.stdout
    exercise_unix_server(compiled)


def test_server_executable_compiled_and_operational():
    assert os.path.isfile(SERVER), f"Executable {SERVER} is missing."
    assert os.access(SERVER, os.X_OK), f"File {SERVER} is not executable."
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Backend server is not a compiled ELF executable"
    exercise_unix_server(SERVER)


def test_backend_and_nginx_work_together():
    stop_configured_nginx()
    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass
    backend = subprocess.Popen([SERVER], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               preexec_fn=demote_to_nginx_user())
    nginx_pid = None
    try:
        wait_for_socket(backend)
        assert stat.S_IMODE(os.stat(SOCKET).st_mode) == 0o600
        start = subprocess.run(["nginx", "-c", CONFIG, "-p", PREFIX],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert start.returncode == 0, start.stdout
        pidfile = Path("/home/user/nginx/nginx.pid")
        deadline = time.time() + 3
        while time.time() < deadline and not pidfile.exists():
            time.sleep(0.03)
        assert pidfile.exists(), "Nginx did not create its PID file"
        nginx_pid = int(pidfile.read_text().strip())
        result = None
        deadline = time.time() + 4
        while time.time() < deadline:
            result = subprocess.run(["curl", "-sS", "http://127.0.0.1:8080/api/status"],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode == 0:
                break
            time.sleep(0.08)
        assert result is not None and result.returncode == 0, result.stderr.decode(errors="ignore")
        assert result.stdout == EXPECTED_BODY, "Live deployment returned the wrong response"
    finally:
        if nginx_pid is not None:
            try:
                os.kill(nginx_pid, 3)
            except ProcessLookupError:
                pass
            deadline = time.time() + 3
            while time.time() < deadline and Path(f"/proc/{nginx_pid}").exists():
                time.sleep(0.05)
        stop_configured_nginx()
        stop_process(backend)
        try:
            os.unlink(SOCKET)
        except FileNotFoundError:
            pass


def test_ci_deploy_script_exists_executable_and_runs_pipeline():
    assert os.path.isfile(SCRIPT), f"Deployment script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Deployment script {SCRIPT} is not executable."
    stop_configured_nginx()
    for pid in running_server_pids():
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    time.sleep(0.15)
    try:
        os.unlink(LOG)
    except FileNotFoundError:
        pass

    wrappers = Path("/tmp/verifier-command-wrappers")
    wrappers.mkdir(exist_ok=True)
    calls = Path("/tmp/verifier-command-calls")
    if calls.exists():
        calls.unlink()
    (wrappers / "nginx").write_text('#!/bin/bash\nprintf "nginx" >> /tmp/verifier-command-calls\nprintf "\\t%s" "$@" >> /tmp/verifier-command-calls\nprintf "\\n" >> /tmp/verifier-command-calls\nexec /usr/sbin/nginx "$@"\n')
    (wrappers / "curl").write_text('#!/bin/bash\nprintf "curl" >> /tmp/verifier-command-calls\nprintf "\\t%s" "$@" >> /tmp/verifier-command-calls\nprintf "\\n" >> /tmp/verifier-command-calls\nexec /usr/bin/curl "$@"\n')
    os.chmod(wrappers / "nginx", 0o755)
    os.chmod(wrappers / "curl", 0o755)
    env = os.environ.copy()
    env["PATH"] = str(wrappers) + ":" + env.get("PATH", "")

    proc = subprocess.Popen([SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    saw_backend = False
    saw_nginx = False
    deadline = time.time() + 15
    while proc.poll() is None and time.time() < deadline:
        saw_backend = saw_backend or bool(running_server_pids())
        saw_nginx = saw_nginx or bool(running_configured_nginx_pids())
        time.sleep(0.02)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
        raise AssertionError("Deployment script did not finish")
    stdout, stderr = proc.communicate()
    assert proc.returncode == 0, (stdout + stderr).decode(errors="ignore")
    assert saw_backend, "Deployment script never ran /home/user/backend/server"
    assert saw_nginx, "Deployment script never started Nginx with the submitted configuration"

    call_rows = [line.split("\t") for line in calls.read_text().splitlines()] if calls.exists() else []
    assert any(row[0] == "nginx" and "-c" in row and CONFIG in row and "-p" in row and PREFIX in row and "-s" not in row for row in call_rows), "Deployment script did not issue the required nginx start command"
    assert any(row[0] == "curl" and "http://127.0.0.1:8080/api/status" in row for row in call_rows), "Deployment script did not use curl on the required URL"

    assert os.path.isfile(LOG), f"Pipeline result log {LOG} is missing."
    assert Path(LOG).read_bytes() == EXPECTED_BODY, "Pipeline log is not the exact curl response"
    time.sleep(0.3)
    assert not running_server_pids(), "Deployment script left the backend running"
    assert not running_configured_nginx_pids(), "Deployment script left Nginx running"


def test_pipeline_result_log_correct():
    assert os.path.isfile(LOG), f"Pipeline result log {LOG} is missing."
    content = Path(LOG).read_text()
    assert '{"status":"secure"}' in content
    assert content == '{"status":"secure"}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
