#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shlex
import signal
import subprocess
import time


def curl_status(url, timeout=2):
    try:
        result = subprocess.run(
            ["curl", "-sS", "--max-time", str(timeout), "-o", "/tmp/verifier_body", "-w", "%{http_code}", url],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout + 2,
        )
        if result.returncode != 0:
            return None, b""
        with open("/tmp/verifier_body", "rb") as f:
            body = f.read()
        return result.stdout.strip(), body
    except (subprocess.TimeoutExpired, OSError):
        return None, b""


def wait_for_status(url, expected, seconds=8):
    deadline = time.time() + seconds
    last = (None, b"")
    while time.time() < deadline:
        last = curl_status(url)
        if last[0] == expected:
            return last
        time.sleep(0.15)
    return last


def process_cmdlines():
    values = []
    for path in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            with open(path, "rb") as f:
                values.append(f.read().replace(b"\0", b" ").decode(errors="replace"))
        except OSError:
            pass
    return values


def run_monitor_clean():
    status_path = "/home/user/status.log"
    with open(status_path, "w"):
        pass
    result = subprocess.run(
        ["bash", "/home/user/monitor.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"monitor.sh failed: {result.stderr}"
    with open(status_path, "r") as f:
        return f.read().splitlines()


def test_backup_exists_and_correct():
    backup_path = "/home/user/backup/nginx.conf.bak"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} does not exist."

    with open(backup_path, "r") as f:
        content = f.read()

    assert "127.0.0.1:8082" in content, "Backup file does not contain the original broken proxy_pass port (8082)."
    expected = """events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8082;
        }
    }
}
"""
    assert content == expected, "The backup is not an exact copy of the original Nginx configuration."


def test_bashrc_backend_port_exported():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist."

    with open(bashrc_path, "r") as f:
        content = f.read()

    normalized_content = content.replace('"', '').replace("'", "")
    assert re.search(r'export\s+BACKEND_PORT=8081\b', normalized_content), "BACKEND_PORT=8081 is not correctly exported in .bashrc."

    sourced = subprocess.run(
        ["bash", "-c", "source /home/user/.bashrc; printf '%s' \"$BACKEND_PORT\""],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert sourced.returncode == 0 and sourced.stdout == "8081", ".bashrc does not actually set BACKEND_PORT to 8081 when sourced."


def test_nginx_config_fixed():
    config_path = "/home/user/nginx_setup/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx config {config_path} does not exist."

    with open(config_path, "r") as f:
        content = f.read()

    assert "127.0.0.1:8081" in content, "Nginx config does not contain the corrected proxy_pass port (8081)."
    checked = subprocess.run(
        ["nginx", "-t", "-c", config_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert checked.returncode == 0, f"Nginx configuration is invalid: {checked.stderr}"


def test_monitor_script_and_status_log_and_running_services():
    monitor_path = "/home/user/monitor.sh"
    status_path = "/home/user/status.log"
    pid_path = "/home/user/nginx_setup/nginx.pid"

    assert os.path.isfile(monitor_path), f"Monitor script {monitor_path} does not exist."
    assert os.path.isfile(status_path), f"Status log {status_path} does not exist. Did you run the monitor script?"

    with open(status_path, "r") as f:
        lines = f.read().splitlines()
    assert any(line.strip() == "UP" for line in lines), "status.log does not contain the word 'UP' indicating a successful health check."

    cmdlines = process_cmdlines()
    assert any("/home/user/backend/start.sh" in cmd for cmd in cmdlines), "The requested backend start.sh service is not running."
    assert os.path.isfile(pid_path), "The requested Nginx pid file does not exist."
    with open(pid_path, "r") as f:
        nginx_pid = int(f.read().strip())
    os.kill(nginx_pid, 0)
    nginx_cmd = open(f"/proc/{nginx_pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
    assert "nginx" in nginx_cmd and "/home/user/nginx_setup/nginx.conf" in nginx_cmd, "The configured user-space Nginx process is not running."

    backend_status, backend_body = wait_for_status("http://127.0.0.1:8081", "200")
    assert backend_status == "200" and b"Hello Backend" in backend_body, "The backend is not serving successfully on port 8081."
    proxy_status, proxy_body = wait_for_status("http://127.0.0.1:8080", "200")
    assert proxy_status == "200" and b"Hello Backend" in proxy_body, "Nginx is not successfully proxying the backend on port 8080."
    assert run_monitor_clean() == ["UP"], "monitor.sh did not append exactly UP for a live HTTP 200 response."

    temp_server = None
    restarted = None
    try:
        os.kill(nginx_pid, signal.SIGTERM)
        deadline = time.time() + 8
        while time.time() < deadline:
            status, _ = curl_status("http://127.0.0.1:8080", timeout=1)
            if status is None:
                break
            time.sleep(0.15)
        assert curl_status("http://127.0.0.1:8080", timeout=1)[0] is None, "Nginx did not stop for controlled monitor testing."

        server_code = """import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(503)
        self.send_header('Content-Length', '0')
        self.end_headers()
    def log_message(self, *args):
        pass
http.server.HTTPServer(('127.0.0.1', 8080), H).serve_forever()
"""
        temp_server = subprocess.Popen(["python3", "-c", server_code], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert wait_for_status("http://127.0.0.1:8080", "503", seconds=5)[0] == "503", "Could not create the controlled non-200 response."
        assert run_monitor_clean() == ["DOWN"], "monitor.sh did not append exactly DOWN for a non-200 HTTP response."

        temp_server.terminate()
        temp_server.wait(timeout=5)
        temp_server = None
        assert run_monitor_clean() == ["DOWN"], "monitor.sh did not append exactly DOWN when the connection failed."
    finally:
        if temp_server is not None and temp_server.poll() is None:
            temp_server.terminate()
            try:
                temp_server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                temp_server.kill()
        restarted = subprocess.Popen(
            ["nginx", "-c", "/home/user/nginx_setup/nginx.conf", "-g", "daemon off; pid /home/user/nginx_setup/nginx.pid;"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

    final_status, final_body = wait_for_status("http://127.0.0.1:8080", "200")
    assert final_status == "200" and b"Hello Backend" in final_body, "Nginx could not be restored after monitor testing."
    assert run_monitor_clean() == ["UP"], "monitor.sh did not append UP after Nginx was restored."


def test_port_forward_script():
    script_path = "/home/user/port_forward.sh"
    assert os.path.isfile(script_path), f"Port forward script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "ssh " in content, "The script does not contain an ssh command."
    assert "dev@example.com" in content, "The script does not connect to dev@example.com."
    assert re.search(r'-[a-zA-Z]*f', content) or " -f" in content, "Missing background flag (-f)."
    assert re.search(r'-[a-zA-Z]*N', content) or " -N" in content, "Missing no-command flag (-N)."
    assert re.search(r'-[a-zA-Z]*q', content) or " -q" in content, "Missing quiet flag (-q)."
    assert re.search(r'-L\s*8080:[a-zA-Z0-9.\-]+:8080', content), "Missing or incorrect local port forwarding rule (-L 8080:host:8080)."

    lines = content.splitlines()
    assert len(lines) == 1 and content.strip() == lines[0], "port_forward.sh must contain only one SSH command."
    try:
        args = shlex.split(lines[0], posix=True)
    except ValueError as exc:
        raise AssertionError(f"Invalid shell syntax in port_forward.sh: {exc}")
    assert args and args[0] == "ssh", "The sole command must be ssh."
    assert args.count("dev@example.com") == 1 and args[-1] == "dev@example.com", "SSH must connect to dev@example.com and must not include a remote command."

    before_destination = args[1:-1]
    forwarding = False
    short_flags = set()
    i = 0
    while i < len(before_destination):
        token = before_destination[i]
        if token == "-L":
            assert i + 1 < len(before_destination), "-L is missing its forwarding specification."
            forwarding = forwarding or before_destination[i + 1] == "8080:example.com:8080"
            i += 2
            continue
        if token.startswith("-L"):
            forwarding = forwarding or token[2:] == "8080:example.com:8080"
            i += 1
            continue
        if token.startswith("-") and not token.startswith("--"):
            short_flags.update(token[1:])
        i += 1

    assert forwarding, "The forwarding rule must be exactly local 8080 to example.com:8080."
    assert {"f", "N", "q"}.issubset(short_flags), "The SSH command must use -f, -N, and -q."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
