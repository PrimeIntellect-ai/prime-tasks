#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import datetime
import json
import os
import re
import shutil
import stat
import subprocess
import time


def test_health_log_exists_and_contains_status_ok():
    log_path = "/home/user/logs/health.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run the script manually and create the directory?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "STATUS: OK" in content, f"Log file {log_path} does not contain the expected string 'STATUS: OK'."


def test_systemd_service_file():
    service_path = "/home/user/.config/systemd/user/health-check.service"
    assert os.path.isfile(service_path), f"Service file {service_path} does not exist."

    config = configparser.ConfigParser(strict=False)
    try:
        config.read(service_path)
    except configparser.MissingSectionHeaderError:
        with open(service_path, "r") as f:
            content = "[DEFAULT]\n" + f.read()
        config.read_string(content)

    exec_start = None
    if "Service" in config:
        exec_start = config["Service"].get("ExecStart")
    elif "DEFAULT" in config:
        exec_start = config["DEFAULT"].get("ExecStart")

    if not exec_start:
        with open(service_path, "r") as f:
            content = f.read()
            assert re.search(r"^ExecStart\s*=\s*/home/user/scripts/health_check\.sh", content, re.MULTILINE), \
                f"Service file {service_path} does not contain the correct ExecStart directive."
    else:
        assert exec_start == "/home/user/scripts/health_check.sh", \
            f"Service file {service_path} has incorrect ExecStart: {exec_start}"


def test_systemd_timer_file():
    timer_path = "/home/user/.config/systemd/user/health-check.timer"
    assert os.path.isfile(timer_path), f"Timer file {timer_path} does not exist."

    with open(timer_path, "r") as f:
        content = f.read()

    assert re.search(r"^OnCalendar\s*=\s*.*(\*:0/5|\*:0,5,10)", content, re.MULTILINE), \
        f"Timer file {timer_path} does not contain a valid OnCalendar directive for every 5 minutes."


def test_health_script_executes_and_performs_required_request():
    script = "/home/user/scripts/health_check.sh"
    assert os.path.exists(script), f"Health check script {script} does not exist."
    assert stat.S_ISREG(os.stat(script, follow_symlinks=False).st_mode), f"{script} must be a regular file."
    assert os.access(script, os.X_OK), f"Health check script {script} is not executable."
    with open(script, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.match(r"^#!\s*(/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)(?:\s|$)", first_line), \
        f"{script} is not a Bash script."

    log_dir = "/home/user/logs"
    request_file = "/tmp/health_check_requests.jsonl"
    ready_file = "/tmp/health_check_server.ready"
    server_file = "/tmp/health_check_test_server.py"

    if os.path.lexists(log_dir):
        if os.path.islink(log_dir) or not os.path.isdir(log_dir):
            os.unlink(log_dir)
        else:
            shutil.rmtree(log_dir)
    for path in (request_file, ready_file):
        if os.path.exists(path):
            os.unlink(path)

    subprocess.run(["pkill", "-f", "[d]ummy_server.py"], check=False)
    if shutil.which("fuser"):
        subprocess.run(["fuser", "-k", "8080/tcp"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.3)

    with open(server_file, "w") as f:
        f.write(r'''import json
from http.server import BaseHTTPRequestHandler, HTTPServer

REQUEST_FILE = "/tmp/health_check_requests.jsonl"
READY_FILE = "/tmp/health_check_server.ready"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(REQUEST_FILE, "a") as out:
            out.write(json.dumps({"method": "GET", "path": self.path}) + "\\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"pong")

    def log_message(self, *args):
        pass

server = HTTPServer(("127.0.0.1", 8080), Handler)
with open(READY_FILE, "w") as out:
    out.write("ready")
server.serve_forever()
''')

    server = subprocess.Popen(["python3", server_file], stdout=subprocess.DEVNULL,
                              stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(ready_file):
            if server.poll() is not None:
                stderr = server.stderr.read()
                raise AssertionError(f"Could not start controlled HTTP server on port 8080: {stderr}")
            time.sleep(0.05)
        assert os.path.exists(ready_file), "Controlled HTTP server did not become ready."

        result = subprocess.run(["runuser", "-u", "user", "--", script],
                                text=True, capture_output=True, timeout=15)
        assert result.returncode == 0, \
            f"Health check script failed when run as user (exit {result.returncode}): {result.stderr}"
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()

    assert os.path.isdir(log_dir) and not os.path.islink(log_dir), \
        "The script did not create /home/user/logs as a directory."
    log_path = os.path.join(log_dir, "health.log")
    assert os.path.isfile(log_path), "The executed script did not create /home/user/logs/health.log."
    with open(log_path) as f:
        lines = [line.rstrip("\r\n") for line in f]
    assert "STATUS: OK" in lines, \
        "A successful HTTP 200 response did not append the exact line 'STATUS: OK'."

    assert os.path.isfile(request_file), "The script did not make an HTTP request to the controlled server."
    with open(request_file) as f:
        requests = [json.loads(line) for line in f if line.strip()]
    assert any(item == {"method": "GET", "path": "/ping"} for item in requests), \
        "The script did not send an HTTP GET request to http://127.0.0.1:8080/ping."


def _directives(path):
    sections = {}
    current = None
    with open(path) as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith(("#", ";")):
                continue
            match = re.fullmatch(r"\[([^]]+)\]", line)
            if match:
                current = match.group(1)
                sections.setdefault(current, [])
                continue
            assert current is not None, f"{path}:{lineno}: directive appears outside a section."
            assert "=" in line, f"{path}:{lineno}: malformed directive."
            key, value = line.split("=", 1)
            sections[current].append((key.strip(), value.strip()))
    return sections


def test_systemd_units_are_valid_and_complete():
    service_path = "/home/user/.config/systemd/user/health-check.service"
    timer_path = "/home/user/.config/systemd/user/health-check.timer"

    service = _directives(service_path)
    timer = _directives(timer_path)
    assert "Service" in service, "health-check.service is missing a [Service] section."
    assert "Timer" in timer, "health-check.timer is missing a [Timer] section."

    exec_starts = [value for key, value in service["Service"] if key == "ExecStart"]
    assert exec_starts == ["/home/user/scripts/health_check.sh"], \
        "[Service] must contain exactly one correct ExecStart directive."

    calendars = [value for key, value in timer["Timer"] if key == "OnCalendar"]
    assert len(calendars) == 1 and calendars[0], \
        "[Timer] must contain exactly one non-empty OnCalendar directive."

    verify = subprocess.run(["systemd-analyze", "verify", service_path, timer_path],
                            text=True, capture_output=True)
    assert verify.returncode == 0, \
        f"The systemd unit files are not valid:\n{verify.stdout}{verify.stderr}"

    env = os.environ.copy()
    env["TZ"] = "UTC"
    calendar = subprocess.run([
        "systemd-analyze", "calendar", "--iterations=13",
        "--base-time=2025-01-01 00:00:01 UTC", calendars[0]
    ], text=True, capture_output=True, env=env)
    assert calendar.returncode == 0, \
        f"Invalid OnCalendar expression {calendars[0]!r}: {calendar.stderr}"

    timestamps = re.findall(
        r"(?:Next elapse|Iter\. #\d+):\s+\w+\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC",
        calendar.stdout,
    )
    assert len(timestamps) >= 12, \
        f"Could not validate the timer schedule produced by {calendars[0]!r}."
    moments = [datetime.datetime.strptime(value, "%Y-%m-%d %H:%M:%S") for value in timestamps]
    intervals = [(b - a).total_seconds() for a, b in zip(moments, moments[1:])]
    assert intervals and all(delta == 300 for delta in intervals), \
        f"OnCalendar={calendars[0]} does not trigger consistently every 5 minutes."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
