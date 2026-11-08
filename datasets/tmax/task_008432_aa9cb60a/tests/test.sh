#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import socket
import stat
import subprocess
import sys
import time
import urllib.request

USER_UNIT_DIR = "/home/user/.config/systemd/user"


def systemctl(*args, check=False):
    return subprocess.run(
        ["systemctl", "--user", *args],
        capture_output=True,
        text=True,
        check=check,
    )


def wait_active(service, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if systemctl("is-active", service).stdout.strip() == "active":
            return
        time.sleep(0.2)
    result = systemctl("status", service)
    raise AssertionError(
        f"Service {service} did not become active. stdout={result.stdout} stderr={result.stderr}"
    )


def read_unit(path):
    sections = {}
    section = None
    pending = ""
    with open(path, encoding="utf-8") as f:
        physical_lines = f.readlines()

    logical_lines = []
    for raw in physical_lines:
        line = raw.rstrip("\n")
        if line.endswith("\\"):
            pending += line[:-1] + " "
            continue
        logical_lines.append(pending + line)
        pending = ""
    if pending:
        logical_lines.append(pending)

    for line in logical_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith(";"):
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
            sections.setdefault(section, {})
            continue
        if section is not None and "=" in line:
            key, value = line.split("=", 1)
            sections[section].setdefault(key.strip(), []).append(value.strip())
    return sections


def directive_words(unit, section, directive):
    values = unit.get(section, {}).get(directive, [])
    words = []
    for value in values:
        words.extend(value.split())
    return words


def main_pid(service):
    result = systemctl("show", service, "--property=MainPID", "--value")
    assert result.returncode == 0, result.stderr
    value = result.stdout.strip()
    assert value.isdigit() and int(value) > 0, f"No valid MainPID for {service}: {value!r}"
    return int(value)


def test_web_backend_service_fixed():
    service_file = os.path.join(USER_UNIT_DIR, "web-backend.service")
    assert os.path.isfile(service_file), f"Missing {service_file}"

    unit = read_unit(service_file)
    assert "log-sink.service" in directive_words(unit, "Unit", "After"), \
        "web-backend.service is missing an effective After=log-sink.service directive"
    assert "log-sink.service" in directive_words(unit, "Unit", "Requires"), \
        "web-backend.service is missing an effective Requires=log-sink.service directive"


def test_frontend_proxy_unit_and_enablement():
    service_file = os.path.join(USER_UNIT_DIR, "frontend-proxy.service")
    assert os.path.isfile(service_file), f"Missing {service_file}"
    unit = read_unit(service_file)
    exec_starts = unit.get("Service", {}).get("ExecStart", [])
    assert exec_starts, "frontend-proxy.service has no ExecStart directive"

    command = exec_starts[-1]
    try:
        argv = shlex.split(command)
    except ValueError as exc:
        raise AssertionError(f"Invalid frontend proxy ExecStart: {exc}")
    assert argv, "frontend-proxy.service has an empty ExecStart"
    executable = argv[0].lstrip("-+!:@")
    assert os.path.basename(executable) == "socat", \
        f"frontend-proxy.service must execute socat, got: {command}"

    args = argv[1:]
    assert any(re.match(r"(?i)^TCP(?:4)?-LISTEN:8443(?:,|$)", arg) for arg in args), \
        f"socat is not configured to listen on TCP port 8443: {command}"
    assert any(re.match(r"(?i)^TCP(?:4)?:127\.0\.0\.1:8080(?:,|$)", arg) for arg in args), \
        f"socat is not configured to forward to 127.0.0.1:8080: {command}"

    enabled = systemctl("is-enabled", "frontend-proxy.service")
    assert enabled.stdout.strip() == "enabled", \
        f"frontend-proxy.service is not enabled: {enabled.stdout.strip()} {enabled.stderr.strip()}"


def test_services_active():
    services = ["log-sink.service", "web-backend.service", "frontend-proxy.service"]
    for svc in services:
        result = systemctl("is-active", svc)
        assert result.stdout.strip() == "active", \
            f"Service {svc} is not active. Output: {result.stdout} {result.stderr}"


def test_frontend_proxy_working():
    try:
        req = urllib.request.Request("http://127.0.0.1:8443")
        with urllib.request.urlopen(req, timeout=5) as response:
            body = response.read().decode("utf-8")
            assert "Hello from backend" in body, \
                "Proxy did not return expected response from backend."
    except Exception as exc:
        raise AssertionError(f"Failed to connect to frontend proxy on port 8443: {exc}")


def test_frontend_is_really_forwarding_to_8080():
    token = "FORWARD_" + secrets.token_hex(16)
    server_code = r'''
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys
TOKEN = sys.argv[1].encode()
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(TOKEN)
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
'''
    custom_backend = None
    systemctl("stop", "web-backend.service", check=True)
    try:
        custom_backend = subprocess.Popen(
            [sys.executable, "-c", server_code, token],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        deadline = time.time() + 5
        while time.time() < deadline:
            if custom_backend.poll() is not None:
                raise AssertionError(
                    f"Temporary backend failed to start: {custom_backend.stderr.read()}"
                )
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise AssertionError("Temporary backend did not bind to port 8080")

        with urllib.request.urlopen("http://127.0.0.1:8443", timeout=5) as response:
            body = response.read().decode("utf-8")
        assert body == token, \
            f"Port 8443 did not forward the dynamically generated response from port 8080: {body!r}"
    finally:
        if custom_backend is not None and custom_backend.poll() is None:
            custom_backend.terminate()
            try:
                custom_backend.wait(timeout=3)
            except subprocess.TimeoutExpired:
                custom_backend.kill()
                custom_backend.wait(timeout=3)
        systemctl("start", "web-backend.service", check=True)
        wait_active("web-backend.service")


def test_symlink_created():
    symlink_path = "/home/user/app/current_logs"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    assert target in ["/home/user/app/logs", "/home/user/app/logs/"], \
        f"Symlink points to wrong target: {target}"


def test_rotate_script():
    script_path = "/home/user/app/rotate.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, encoding="utf-8") as f:
        script_content = f.read().replace("\\\n", " ")
    restart_command = re.compile(
        r"(?m)^\s*(?:if\s+)?(?:/usr/bin/)?systemctl\s+--user\s+restart\s+"
        r"log-sink\.service(?=\s*(?:$|;|&&|\|\|))"
    )
    assert restart_command.search(script_content), \
        "rotate.sh does not invoke 'systemctl --user restart log-sink.service'"

    log_file = "/home/user/app/logs/server.log"
    archive_file = "/home/user/app/logs/server.log.archive"
    status_file = "/home/user/app/rotation_status.txt"
    for path in (archive_file, status_file):
        if os.path.lexists(path):
            os.unlink(path)

    wait_active("log-sink.service")
    old_pid = main_pid("log-sink.service")
    marker = "ROTATE_SOURCE_" + secrets.token_hex(16)
    with open(log_file, "a", encoding="utf-8") as f:
        f.write(marker + "\n")

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, \
        f"rotate.sh failed with exit code {result.returncode}. stderr: {result.stderr}"

    assert os.path.isfile(archive_file), f"Archive file {archive_file} was not created."
    with open(archive_file, encoding="utf-8") as f:
        archive_content = f.read()
    assert marker in archive_content, \
        "The archive does not contain the pre-rotation server.log contents"

    assert os.path.isfile(status_file), f"Status file {status_file} was not created."
    with open(status_file, encoding="utf-8") as f:
        status_content = f.read()
    assert "ROTATION_COMPLETE" in status_content, \
        f"String 'ROTATION_COMPLETE' not found in {status_file}"

    wait_active("log-sink.service")
    new_pid = main_pid("log-sink.service")
    assert new_pid != old_pid, \
        "log-sink.service was not restarted by rotate.sh"

    deadline = time.time() + 5
    while time.time() < deadline and not os.path.isfile(log_file):
        time.sleep(0.1)
    assert os.path.isfile(log_file), \
        "rotate.sh did not recreate server.log by restarting log-sink.service"
    with open(log_file, encoding="utf-8") as f:
        new_log = f.read()
    assert "Log sink started" in new_log, \
        "The recreated server.log was not produced by the restarted log sink"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
