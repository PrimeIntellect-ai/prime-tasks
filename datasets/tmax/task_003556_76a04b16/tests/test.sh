#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import time
import signal
import shutil
import socket
import subprocess
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer


def fetch(url, timeout=1):
    last = None
    for _ in range(30):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as response:
                return response.read()
        except Exception as exc:
            last = exc
            time.sleep(0.1)
    raise AssertionError(f"Could not fetch {url}: {last}")


def kill_matching(pattern):
    subprocess.run(["pkill", "-TERM", "-f", pattern], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)
    subprocess.run(["pkill", "-KILL", "-f", pattern], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def stop_services():
    kill_matching("/home/user/scripts/supervisor.sh")
    kill_matching("python3 -m http.server 8081")
    subprocess.run(["nginx", "-s", "stop", "-p", "/home/user/nginx",
                    "-c", "/home/user/nginx/nginx.conf"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    kill_matching("nginx: master process")
    time.sleep(0.3)


def stop_process_group(proc):
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=1)


def wait_for_count(path, minimum, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(path) as f:
                if int(f.read().strip()) >= minimum:
                    return
        except (FileNotFoundError, ValueError):
            pass
        time.sleep(0.05)
    raise AssertionError(f"Supervisor did not restart backend to invocation {minimum} promptly")


def test_complete_final_state():
    config_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx config {config_path} is missing."
    with open(config_path, "r") as f:
        content = f.read()
        assert "proxy_pass http://127.0.0.1:8081" in content or "proxy_pass http://localhost:8081" in content, \
            "Nginx config does not contain the corrected proxy_pass port (8081)."

    script_path = "/home/user/scripts/supervisor.sh"
    assert os.path.isfile(script_path), f"Supervisor script {script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Supervisor script {script_path} is not executable."

    with open(script_path, "r") as f:
        script_content = f.read()
    assert "while" in script_content or "until" in script_content, "Supervisor script does not appear to contain a loop."
    assert "/home/user/app/backend.sh" in script_content, "Supervisor script does not execute the backend script."
    assert "/home/user/logs/backend.log" in script_content, "Supervisor script does not redirect to the expected log file."
    assert "1024" in script_content, "Supervisor script does not contain the 1024 byte size check."
    assert "backend.log.old" in script_content, "Supervisor script does not rename to backend.log.old."
    assert "Subject: Backend Crash Alert" in script_content, "Supervisor script does not contain the required alert subject."
    assert "/home/user/mail/alerts" in script_content, "Supervisor script does not write to the alerts file."

    success_path = "/home/user/success.txt"
    assert os.path.isfile(success_path), f"Success file {success_path} is missing."
    with open(success_path, "rb") as f:
        saved_success = f.read()
    assert b"Directory listing" in saved_success, "Success file does not contain the expected output from the backend service."

    # The requested deployment must really be running, and success.txt must be the
    # exact body currently returned through nginx rather than fabricated text.
    deployed_body = fetch("http://127.0.0.1:8080/")
    assert deployed_body == saved_success, \
        "success.txt is not the exact output returned by the deployed service."

    backend_path = "/home/user/app/backend.sh"
    backup_path = "/tmp/backend.sh.verifier-backup"
    shutil.copy2(backend_path, backup_path)
    supervisor_proc = None
    boundary_proc = None
    nginx_started = False

    try:
        stop_services()

        # Execute the submitted nginx configuration against an unpredictable
        # backend response. This proves proxy_pass is active and targets 8081,
        # rather than merely appearing in a comment.
        token = os.urandom(24).hex().encode()

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                body = token + self.path.encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            def log_message(self, *args):
                pass

        server = HTTPServer(("127.0.0.1", 8081), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            syntax = subprocess.run(
                ["nginx", "-t", "-p", "/home/user/nginx", "-c", config_path],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            assert syntax.returncode == 0, \
                "Submitted nginx configuration is invalid: " + syntax.stderr.decode(errors="replace")
            started = subprocess.run(
                ["nginx", "-p", "/home/user/nginx", "-c", config_path],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            assert started.returncode == 0, \
                "Nginx could not start with the submitted configuration: " + started.stderr.decode(errors="replace")
            nginx_started = True
            challenge_path = "/verify-" + os.urandom(8).hex()
            assert fetch("http://127.0.0.1:8080" + challenge_path) == token + challenge_path.encode(), \
                "Nginx did not proxy requests to the backend on port 8081."
        finally:
            if nginx_started:
                subprocess.run(["nginx", "-s", "stop", "-p", "/home/user/nginx", "-c", config_path],
                               check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                nginx_started = False
            server.shutdown()
            server.server_close()
            thread.join(timeout=1)

        os.makedirs("/home/user/logs", exist_ok=True)
        os.makedirs("/home/user/mail", exist_ok=True)
        count_path = "/tmp/supervisor-verifier-count"
        overlap_path = "/tmp/supervisor-verifier-overlap"
        for path in [count_path, overlap_path, "/home/user/mail/alerts"]:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        old_seed = b"previous backup must be overwritten"
        large_seed = b"R" * 1025
        with open("/home/user/logs/backend.log", "wb") as f:
            f.write(large_seed)
        with open("/home/user/logs/backend.log.old", "wb") as f:
            f.write(old_seed)

        fixture = r'''#!/bin/bash
lock=/tmp/supervisor-verifier-lock
if ! mkdir "$lock" 2>/dev/null; then
    echo overlap > /tmp/supervisor-verifier-overlap
    exit 19
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT
count=0
if [ -f /tmp/supervisor-verifier-count ]; then count=$(cat /tmp/supervisor-verifier-count); fi
count=$((count + 1))
echo "$count" > /tmp/supervisor-verifier-count
echo "STDOUT_RUN_$count"
echo "STDERR_RUN_$count" >&2
if [ "$count" -eq 1 ]; then exit 7; fi
if [ "$count" -eq 2 ]; then exit 0; fi
sleep 30
'''
        with open(backend_path, "w") as f:
            f.write(fixture)
        os.chmod(backend_path, 0o755)

        supervisor_proc = subprocess.Popen(
            [script_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)
        wait_for_count(count_path, 3)
        time.sleep(0.2)
        assert supervisor_proc.poll() is None, "Supervisor exited instead of continuing its infinite loop."
        assert not os.path.exists(overlap_path), \
            "Supervisor started overlapping backend instances instead of running each in the foreground."

        with open("/home/user/logs/backend.log.old", "rb") as f:
            assert f.read() == large_seed, \
                "A log larger than 1024 bytes was not rotated to backend.log.old with the old backup overwritten."
        with open("/home/user/logs/backend.log", "rb") as f:
            log_data = f.read()
        for marker in [b"STDOUT_RUN_1", b"STDERR_RUN_1", b"STDOUT_RUN_2", b"STDERR_RUN_2", b"STDOUT_RUN_3", b"STDERR_RUN_3"]:
            assert marker in log_data, f"Backend output was not retained in backend.log: missing {marker!r}."

        with open("/home/user/mail/alerts", "rb") as f:
            alert_lines = f.read().splitlines()
        assert alert_lines == [b"Subject: Backend Crash Alert"], \
            "Supervisor must append exactly one crash alert for the non-zero exit and none for the zero exit."

        stop_process_group(supervisor_proc)
        supervisor_proc = None
        kill_matching(backend_path)
        try:
            os.rmdir("/tmp/supervisor-verifier-lock")
        except OSError:
            pass

        # Exactly 1024 bytes must not rotate because the threshold is strictly greater.
        with open("/home/user/logs/backend.log", "wb") as f:
            f.write(b"B" * 1024)
        try:
            os.remove("/home/user/logs/backend.log.old")
        except FileNotFoundError:
            pass
        boundary_fixture = r'''#!/bin/bash
echo BOUNDARY_MARKER
echo BOUNDARY_STDERR >&2
sleep 30
'''
        with open(backend_path, "w") as f:
            f.write(boundary_fixture)
        os.chmod(backend_path, 0o755)
        boundary_proc = subprocess.Popen(
            [script_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)
        deadline = time.time() + 3
        boundary_data = b""
        while time.time() < deadline:
            try:
                with open("/home/user/logs/backend.log", "rb") as f:
                    boundary_data = f.read()
            except FileNotFoundError:
                pass
            if b"BOUNDARY_MARKER" in boundary_data and b"BOUNDARY_STDERR" in boundary_data:
                break
            time.sleep(0.05)
        assert b"BOUNDARY_MARKER" in boundary_data and b"BOUNDARY_STDERR" in boundary_data, \
            "Supervisor did not redirect backend stdout and stderr to backend.log."
        assert boundary_data.startswith(b"B" * 1024), \
            "Supervisor did not preserve the existing 1024-byte log when starting the backend."
        assert not os.path.exists("/home/user/logs/backend.log.old"), \
            "Supervisor rotated a log of exactly 1024 bytes; rotation must occur only when strictly greater."
    finally:
        stop_process_group(supervisor_proc)
        stop_process_group(boundary_proc)
        stop_services()
        if os.path.exists(backup_path):
            shutil.copy2(backup_path, backend_path)
            os.remove(backup_path)
        for path in ["/tmp/supervisor-verifier-count", "/tmp/supervisor-verifier-overlap"]:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        try:
            os.rmdir("/tmp/supervisor-verifier-lock")
        except OSError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
