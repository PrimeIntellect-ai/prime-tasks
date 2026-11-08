#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import pwd
import re
import secrets
import shlex
import signal
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

SUPERVISOR_CFG = "/home/user/supervisor/supervisord.conf"
HAPROXY_CFG = "/home/user/haproxy/haproxy.cfg"
API_SCRIPT = "/home/user/uptime_api.py"
CHECK_SCRIPT = "/home/user/check_health.py"
HEALTH_LOG = "/home/user/health_log.txt"
USER_UID = pwd.getpwnam("user").pw_uid


def proc_info():
    result = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
            cmdline = [x.decode(errors="replace") for x in cmdline if x]
            status = Path(f"/proc/{pid}/status").read_text()
            ppid = int(re.search(r"^PPid:\s+(\d+)", status, re.M).group(1))
            uid = int(re.search(r"^Uid:\s+(\d+)", status, re.M).group(1))
            result[pid] = {"cmd": cmdline, "ppid": ppid, "uid": uid}
        except (FileNotFoundError, ProcessLookupError, PermissionError, AttributeError):
            pass
    return result


def descendants(root_pid, processes):
    found = set()
    changed = True
    while changed:
        changed = False
        for pid, info in processes.items():
            if pid not in found and (info["ppid"] == root_pid or info["ppid"] in found):
                found.add(pid)
                changed = True
    return found


def http_result(url, timeout=2):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def wait_for(predicate, timeout=15, interval=0.2):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except Exception as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise AssertionError(f"condition was not met: {last_error}")
    raise AssertionError("condition was not met before timeout")


def configured_supervisord_pids():
    matches = []
    for pid, info in proc_info().items():
        cmd = info["cmd"]
        if not cmd or not any("supervisord" in os.path.basename(arg) for arg in cmd):
            continue
        for i, arg in enumerate(cmd[:-1]):
            if arg in ("-c", "--configuration"):
                candidate = cmd[i + 1]
                if not os.path.isabs(candidate):
                    try:
                        candidate = os.path.join(os.readlink(f"/proc/{pid}/cwd"), candidate)
                    except OSError:
                        continue
                if os.path.realpath(candidate) == os.path.realpath(SUPERVISOR_CFG):
                    matches.append(pid)
    return matches


def supervised_api_pids():
    processes = proc_info()
    roots = configured_supervisord_pids()
    matches = []
    for root in roots:
        for pid in descendants(root, processes):
            cmd = processes[pid]["cmd"]
            if any(os.path.realpath(arg) == API_SCRIPT for arg in cmd if arg.startswith("/")):
                matches.append(pid)
    return matches


def test_supervisord_running():
    """Verify that supervisord is running."""
    try:
        result = subprocess.run(['pgrep', 'supervisord'], capture_output=True, text=True)
        assert result.returncode == 0, "supervisord process is not running."
        assert result.stdout.strip(), "No PID found for supervisord."
    except FileNotFoundError:
        pytest.fail("pgrep command not found.")


def test_haproxy_running():
    """Verify that haproxy is running."""
    try:
        result = subprocess.run(['pgrep', 'haproxy'], capture_output=True, text=True)
        assert result.returncode == 0, "haproxy process is not running."
        assert result.stdout.strip(), "No PID found for haproxy."
    except FileNotFoundError:
        pytest.fail("pgrep command not found.")


def test_haproxy_cfg_permissions():
    """Verify that /home/user/haproxy/haproxy.cfg has exactly 400 permissions."""
    cfg_path = HAPROXY_CFG
    assert os.path.isfile(cfg_path), f"HAProxy configuration file not found at {cfg_path}."
    stat_info = os.stat(cfg_path)
    permissions = stat_info.st_mode & 0o777
    assert permissions == 0o400, f"Expected permissions 400, but got {oct(permissions)} for {cfg_path}."


def test_health_log_contents():
    """Verify that /home/user/health_log.txt exists and contains the correct JSON."""
    log_path = HEALTH_LOG
    assert os.path.isfile(log_path), f"Health log file not found at {log_path}."
    with open(log_path, 'r') as f:
        content = f.read().strip()
    assert content, f"File {log_path} is empty."
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"Content of {log_path} is not valid JSON. Content: {content}")
    assert data.get("status") == "UP", f"Expected status 'UP', got {data.get('status')}."
    assert data.get("uptime") == 9999, f"Expected uptime 9999, got {data.get('uptime')}."


def test_configs_processes_proxy_supervision_and_monitor():
    assert os.path.isfile(SUPERVISOR_CFG), "supervisord.conf is missing"
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.read(SUPERVISOR_CFG)
    program_sections = [s for s in parser.sections() if s.lower().startswith("program:")]
    valid_program = False
    for section in program_sections:
        if not parser.has_option(section, "command"):
            continue
        command = shlex.split(parser.get(section, "command"))
        if not command or os.path.basename(command[0]) != "python3":
            continue
        if API_SCRIPT not in command:
            continue
        if parser.get(section, "autorestart", fallback="").strip().lower() != "true":
            continue
        valid_program = True
    assert valid_program, "A [program:*] must run uptime_api.py with python3 and autorestart=true"

    supervisor_pids = configured_supervisord_pids()
    assert supervisor_pids, "No running supervisord uses the required supervisord.conf"
    processes = proc_info()
    assert all(processes[p]["uid"] == USER_UID for p in supervisor_pids), "supervisord is not running as user"
    api_pids = supervised_api_pids()
    assert api_pids, "uptime_api.py is not a descendant of the configured supervisord"
    assert all(proc_info()[p]["uid"] == USER_UID for p in api_pids), "uptime_api.py is not running as user"

    validation = subprocess.run(["haproxy", "-c", "-f", HAPROXY_CFG], capture_output=True, text=True)
    assert validation.returncode == 0, f"Invalid HAProxy configuration: {validation.stdout}{validation.stderr}"
    cfg_text = Path(HAPROXY_CFG).read_text()
    lines = [line.split("#", 1)[0].strip() for line in cfg_text.splitlines()]
    sections = {}
    current = None
    for line in lines:
        if not line:
            continue
        match = re.match(r"^(frontend|backend)\s+(\S+)", line, re.I)
        if match:
            current = (match.group(1).lower(), match.group(2))
            sections[current] = []
        elif re.match(r"^(global|defaults|listen)\b", line, re.I):
            current = None
        elif current:
            sections[current].append(line)

    valid_route = False
    for (kind, name), frontend_lines in sections.items():
        if kind != "frontend":
            continue
        binds = [line for line in frontend_lines if re.match(r"^bind\s+127\.0\.0\.1:8080(?:\s|$)", line, re.I)]
        defaults = [re.split(r"\s+", line)[1] for line in frontend_lines if re.match(r"^default_backend\s+\S+", line, re.I)]
        if not binds:
            continue
        for backend_name in defaults:
            backend_lines = sections.get(("backend", backend_name), [])
            if any(re.match(r"^server\s+\S+\s+127\.0\.0\.1:9000(?:\s|$)", line, re.I) for line in backend_lines):
                valid_route = True
    assert valid_route, "HAProxy must default-route the 127.0.0.1:8080 frontend to a 127.0.0.1:9000 backend"

    haproxy_matches = []
    for pid, info in proc_info().items():
        cmd = info["cmd"]
        if not cmd or not any("haproxy" == os.path.basename(arg) for arg in cmd):
            continue
        if any(os.path.realpath(arg) == HAPROXY_CFG for arg in cmd if arg.startswith("/")):
            haproxy_matches.append(pid)
    assert haproxy_matches, "No running HAProxy process uses the required haproxy.cfg"
    assert all(proc_info()[p]["uid"] == USER_UID for p in haproxy_matches), "HAProxy is not running as user"

    direct = http_result("http://127.0.0.1:9000/health")
    proxied = http_result("http://127.0.0.1:8080/health")
    assert direct == proxied and direct[0] == 200, "A request through HAProxy does not reach the API"
    random_path = "/verifier-" + secrets.token_hex(8)
    assert http_result("http://127.0.0.1:8080" + random_path) == http_result("http://127.0.0.1:9000" + random_path), "HAProxy does not forward arbitrary paths"

    assert os.path.isfile(CHECK_SCRIPT), "check_health.py is missing"
    check_source = Path(CHECK_SCRIPT).read_text()
    assert "http://127.0.0.1:8080/health" in check_source, "check_health.py does not target the required proxy URL"
    assert HEALTH_LOG in check_source, "check_health.py does not target the required log path"

    original_api = Path(API_SCRIPT).read_bytes()
    challenge = ('{"nonce":"' + secrets.token_hex(24) + '","status":"CHALLENGE"}').encode()
    challenge_source = b'''#!/usr/bin/env python3\nimport http.server\nBODY = ''' + repr(challenge).encode() + b'''\nclass H(http.server.BaseHTTPRequestHandler):\n    def do_GET(self):\n        if self.path == "/health":\n            self.send_response(200)\n            self.send_header("Content-Type", "application/json")\n            self.end_headers()\n            self.wfile.write(BODY)\n        else:\n            self.send_response(404)\n            self.end_headers()\n    def log_message(self, *args):\n        pass\nhttp.server.HTTPServer(("127.0.0.1", 9000), H).serve_forever()\n'''

    try:
        Path(API_SCRIPT).write_bytes(challenge_source)
        old_pids = set(supervised_api_pids())
        assert old_pids, "No supervised API process was available for restart testing"
        for pid in old_pids:
            os.kill(pid, signal.SIGTERM)

        def challenge_is_live():
            new_pids = set(supervised_api_pids()) - old_pids
            if not new_pids:
                return False
            return http_result("http://127.0.0.1:8080/health") == (200, challenge)

        wait_for(challenge_is_live)
        Path(HEALTH_LOG).write_bytes(b"VERIFIER_SENTINEL")
        run = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", CHECK_SCRIPT],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert run.returncode == 0, f"check_health.py failed: {run.stdout}{run.stderr}"
        assert Path(HEALTH_LOG).read_bytes() == challenge, "check_health.py did not write the exact live response body"
    finally:
        Path(API_SCRIPT).write_bytes(original_api)
        for pid in supervised_api_pids():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

        def original_is_live():
            status, body = http_result("http://127.0.0.1:8080/health")
            if status != 200:
                return False
            try:
                return json.loads(body) == {"status": "UP", "uptime": 9999}
            except Exception:
                return False

        wait_for(original_is_live)
        subprocess.run(["runuser", "-u", "user", "--", "python3", CHECK_SCRIPT], timeout=10, check=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
