#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import signal
import socket
import subprocess
import time

ORIGINAL_CONFIG = '''worker_processes 1;
daemon off;
error_log /home/user/app/logs/error.log;
pid /home/user/app/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/app/logs/access.log;

    upstream cpp_backend {
        # Intentional 502 bad gateway trigger
        server 127.0.0.1:9999;
    }

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://cpp_backend;
        }
    }
}
'''


def direct_health():
    with socket.create_connection(("127.0.0.1", 8081), timeout=2) as sock:
        sock.sendall(b"GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks)


def proxy_health():
    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=2)
    try:
        conn.request("GET", "/health")
        response = conn.getresponse()
        return response.status, response.read()
    finally:
        conn.close()


def retry(call, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return call()
        except Exception as exc:
            last_error = exc
            time.sleep(0.15)
    raise AssertionError(f"Service did not become ready: {last_error}")


def process_executable(pid):
    return os.path.realpath(os.readlink(f"/proc/{pid}/exe"))


def backend_pids():
    expected = os.path.realpath("/home/user/app/backend")
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if process_executable(int(entry)) == expected:
                found.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def stop_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def exercise_backend(executable):
    backend = subprocess.Popen([executable], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    nginx = None
    try:
        raw = retry(direct_health)
        assert raw == b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK", (
            f"Backend returned an incorrect raw health response: {raw!r}"
        )

        nginx = subprocess.Popen(
            ["nginx", "-c", "/home/user/app/conf/nginx.conf"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        status, body = retry(proxy_health)
        assert status == 200, f"Nginx health request returned HTTP {status}."
        assert body == b"OK", f"Nginx health request returned {body!r} instead of b'OK'."
    finally:
        if nginx is not None:
            nginx.terminate()
            try:
                nginx.wait(timeout=3)
            except subprocess.TimeoutExpired:
                nginx.kill()
                nginx.wait()
        backend.terminate()
        try:
            backend.wait(timeout=3)
        except subprocess.TimeoutExpired:
            backend.kill()
            backend.wait()
        time.sleep(0.2)


def test_backup_and_directories():
    backup_file = "/home/user/backup/nginx.conf.bak"
    logs_dir = "/home/user/app/logs"

    assert os.path.isfile(backup_file), f"Backup file {backup_file} is missing."
    assert os.path.isdir(logs_dir), f"Logs directory {logs_dir} is missing."
    with open(backup_file, "r") as f:
        backup_content = f.read()
    assert backup_content == ORIGINAL_CONFIG, "Backup is not an unchanged copy of the original Nginx config."


def test_symlink():
    symlink_path = "/home/user/active_conf"
    target_path = "/home/user/app/conf/nginx.conf"

    assert os.path.islink(symlink_path), f"Symlink {symlink_path} is missing or is not a symlink."
    target = os.readlink(symlink_path)
    assert target == target_path, f"Symlink points to {target} instead of {target_path}."


def test_nginx_config_updated():
    conf_path = "/home/user/app/conf/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config {conf_path} is missing."

    with open(conf_path, "r") as f:
        content = f.read()

    assert "127.0.0.1:9999" not in content, "Nginx config still points to the broken port 9999."
    assert "127.0.0.1:8081" in content, "Nginx config does not point to the correct backend port 8081."
    assert "pid /home/user/app/nginx.pid;" in content, "Nginx pid path is incorrect."
    assert "error_log /home/user/app/logs/error.log;" in content, "Nginx error log path is incorrect."
    result = subprocess.run(
        ["nginx", "-t", "-c", conf_path], capture_output=True, text=True
    )
    assert result.returncode == 0, f"Nginx configuration is invalid: {result.stderr}"


def test_backend_compiled():
    backend_path = "/home/user/app/backend"
    assert os.path.isfile(backend_path), f"Compiled backend {backend_path} is missing."
    assert os.access(backend_path, os.X_OK), f"Compiled backend {backend_path} is not executable."
    with open(backend_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Backend is not a compiled ELF executable."


def test_resolution_log():
    log_path = "/home/user/resolution.log"
    assert os.path.isfile(log_path), f"Resolution log {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read()

    assert "OK" in content, f"Resolution log does not contain 'OK'. Actual content: {content.strip()}"
    assert content == "OK", f"Resolution log is not the raw successful curl body: {content!r}"


def test_running_services_and_artifacts():
    nginx_pid_path = "/home/user/app/nginx.pid"
    assert os.path.isfile(nginx_pid_path), "Nginx pid file is missing."
    with open(nginx_pid_path) as f:
        nginx_pid = int(f.read().strip())
    assert "nginx" in os.path.basename(process_executable(nginx_pid)), "Recorded Nginx process is not running."

    running_backends = backend_pids()
    assert running_backends, "The compiled backend process is not running."

    raw = retry(direct_health)
    assert raw == b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK", (
        f"Running backend returned an incorrect health response: {raw!r}"
    )
    status, body = retry(proxy_health)
    assert status == 200, f"Running Nginx proxy returned HTTP {status}."
    assert body == b"OK", f"Running Nginx proxy returned {body!r} instead of b'OK'."

    stop_pid(nginx_pid)
    for pid in running_backends:
        stop_pid(pid)
    time.sleep(0.3)

    exercise_backend("/home/user/app/backend")

    rebuilt = "/tmp/backend_from_submitted_source"
    subprocess.run(
        ["g++", "/home/user/app/src/server.cpp", "-o", rebuilt],
        check=True,
        capture_output=True,
        text=True,
    )
    exercise_backend(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
