#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import stat
import subprocess
import time
import pytest

SOCKET = "/home/user/app/sockets/backend.sock"
NGINX_CONF = "/home/user/nginx/nginx.conf"
NGINX_PREFIX = "/home/user/nginx/"
NGINX_PID = "/home/user/nginx/nginx.pid"
ERROR_LOG = "/home/user/nginx/logs/error.log"
ROTATED_LOG = "/home/user/nginx/logs/error.log.1"


def curl_url(url, extra=None):
    cmd = ["curl", "-sS", "--max-time", "2", "-o", "/tmp/verifier_body", "-w", "%{http_code}"]
    if extra:
        cmd.extend(extra)
    cmd.append(url)
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    body = ""
    if os.path.exists("/tmp/verifier_body"):
        with open("/tmp/verifier_body", "r") as f:
            body = f.read()
    return proc.returncode, proc.stdout.strip(), body


def stop_socket_listeners():
    needle = b"UNIX-LISTEN:" + SOCKET.encode()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read()
            if b"socat" in cmdline and needle in cmdline:
                os.kill(int(name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)
    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass


def stop_nginx():
    try:
        with open(NGINX_PID, "r") as f:
            pid = int(f.read().strip())
        os.kill(pid, signal.SIGTERM)
        for _ in range(30):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
    except (FileNotFoundError, ValueError, ProcessLookupError):
        pass
    try:
        os.unlink(NGINX_PID)
    except FileNotFoundError:
        pass


def test_success_txt():
    success_file = "/home/user/success.txt"
    assert os.path.isfile(success_file), f"File {success_file} does not exist. Did you run the curl command?"

    with open(success_file, "r") as f:
        content = f.read().strip()

    assert content == "Backend operational.", f"Expected 'Backend operational.' in {success_file}, but got '{content}'"


def test_sockets_directory():
    sockets_dir = "/home/user/app/sockets"
    assert os.path.exists(sockets_dir), f"Path {sockets_dir} does not exist."
    assert os.path.isdir(sockets_dir), f"Path {sockets_dir} is not a directory."
    assert not os.path.islink(sockets_dir), f"Path {sockets_dir} is still a symlink."


def test_sockets_permissions():
    sockets_dir = "/home/user/app/sockets"
    assert os.path.exists(sockets_dir), f"Path {sockets_dir} does not exist."

    st = os.stat(sockets_dir)
    perms = oct(st.st_mode)[-3:]
    assert perms == "755", f"Expected permissions 755 for {sockets_dir}, but got {perms}"


def test_bashrc_env():
    bashrc_file = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_file), f"File {bashrc_file} does not exist."

    with open(bashrc_file, "r") as f:
        content = f.read()

    pattern = r"BACKEND_SOCKET\s*=\s*[\"']?/home/user/app/sockets/backend\.sock[\"']?"
    assert re.search(pattern, content), f"BACKEND_SOCKET is not correctly set in {bashrc_file}"

    proc = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-ic", "sh -c 'printf %s \"$BACKEND_SOCKET\"'"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert proc.returncode == 0, f"Could not load the user profile: {proc.stderr}"
    assert proc.stdout == SOCKET, "BACKEND_SOCKET is not exported correctly by the interactive user profile"


def test_live_backend_and_proxy():
    backend_script = "/home/user/app/start_backend.sh"
    assert os.path.isfile(backend_script), f"File {backend_script} does not exist."
    assert os.access(backend_script, os.X_OK), f"File {backend_script} is not executable."

    stop_socket_listeners()
    stop_nginx()

    check = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF, "-p", NGINX_PREFIX],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert check.returncode == 0, f"Nginx configuration is invalid: {check.stderr}"

    start = subprocess.run(
        ["nginx", "-c", NGINX_CONF, "-p", NGINX_PREFIX],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert start.returncode == 0, f"Nginx failed to start: {start.stderr}"

    # With no UNIX socket listener, the configured proxy must fail rather than
    # serving a fabricated static success response.
    missing_status = None
    for _ in range(20):
        _, missing_status, _ = curl_url("http://127.0.0.1:8080")
        if missing_status:
            break
        time.sleep(0.1)
    assert missing_status == "502", f"Expected Nginx to return 502 without the backend, got {missing_status!r}"

    launch = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-ic", "exec /home/user/app/start_backend.sh"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5
    )
    assert launch.returncode == 0, "start_backend.sh failed when run with the user's profile"

    for _ in range(40):
        if os.path.exists(SOCKET) and stat.S_ISSOCK(os.stat(SOCKET).st_mode):
            break
        time.sleep(0.1)
    assert os.path.exists(SOCKET), "start_backend.sh did not create the configured socket"
    socket_stat = os.stat(SOCKET)
    assert stat.S_ISSOCK(socket_stat.st_mode), f"{SOCKET} is not a UNIX socket"
    assert socket_stat.st_mode & 0o006 == 0o006, "The backend socket is not readable and writable by the Nginx worker"

    direct = None
    for _ in range(30):
        direct = curl_url("http://localhost/", ["--unix-socket", SOCKET])
        if direct[1] == "200":
            break
        time.sleep(0.1)
    assert direct[1] == "200", f"The backend socket did not return HTTP 200: {direct}"
    assert direct[2].strip() == "Backend operational.", f"Unexpected direct backend response: {direct[2]!r}"

    proxied = None
    for _ in range(30):
        proxied = curl_url("http://127.0.0.1:8080")
        if proxied[1] == "200":
            break
        time.sleep(0.1)
    assert proxied[1] == "200", f"Nginx did not proxy a successful HTTP response: {proxied}"
    assert proxied[2].strip() == "Backend operational.", f"Unexpected proxied response: {proxied[2]!r}"

    with open("/home/user/success.txt", "r") as f:
        saved = f.read()
    assert saved.strip() == proxied[2].strip(), "success.txt does not match the live response returned through Nginx"


def test_rotate_logs_script():
    script_file = "/home/user/scripts/rotate_logs.sh"
    assert os.path.isfile(script_file), f"File {script_file} does not exist."
    assert os.access(script_file, os.X_OK), f"File {script_file} is not executable."

    with open(script_file, "r") as f:
        content = f.read()

    assert "mv " in content and "error.log" in content and "error.log.1" in content, \
        f"{script_file} does not seem to move error.log to error.log.1"
    assert "USR1" in content and ("kill" in content or "nginx -s" in content), \
        f"{script_file} does not seem to send USR1 signal to nginx."

    assert os.path.isfile(NGINX_PID), "Nginx master PID file is missing"
    with open(NGINX_PID, "r") as f:
        master_pid = int(f.read().strip())
    os.kill(master_pid, 0)

    marker = f"verifier-rotation-marker-{time.time_ns()}"
    with open(ERROR_LOG, "a") as f:
        f.write(marker + "\n")
        f.flush()
        os.fsync(f.fileno())
    old_inode = os.stat(ERROR_LOG).st_ino

    proc = subprocess.run([script_file], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert proc.returncode == 0, f"Log rotation script failed: {proc.stderr}"

    for _ in range(40):
        if os.path.isfile(ERROR_LOG) and os.stat(ERROR_LOG).st_ino != old_inode:
            break
        time.sleep(0.1)

    assert os.path.isfile(ROTATED_LOG), "The rotated error.log.1 file was not created"
    assert os.stat(ROTATED_LOG).st_ino == old_inode, "error.log was not actually moved to error.log.1"
    with open(ROTATED_LOG, "r", errors="replace") as f:
        assert marker in f.read(), "The old error log contents were not preserved in error.log.1"

    assert os.path.isfile(ERROR_LOG), "Nginx did not reopen error.log after rotation"
    new_inode = os.stat(ERROR_LOG).st_ino
    assert new_inode != old_inode, "Nginx is still using the rotated log inode"
    os.kill(master_pid, 0)

    open_inodes = set()
    fd_dir = f"/proc/{master_pid}/fd"
    for fd in os.listdir(fd_dir):
        try:
            open_inodes.add(os.stat(os.path.join(fd_dir, fd)).st_ino)
        except FileNotFoundError:
            pass
    assert new_inode in open_inodes, "The Nginx master did not reopen the new error.log after rotation"

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
