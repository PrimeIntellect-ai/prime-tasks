#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import socket
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

NETMON_DIR = "/home/user/netmon"
MONITOR = os.path.join(NETMON_DIR, "monitor.py")


def test_files_exist():
    """Verify all required files exist."""
    expected_files = [
        "targets.txt",
        "routing.json",
        "fallback_route.sh",
        "monitor.py",
        "connectivity.log",
        "cron_backup.txt",
    ]
    for filename in expected_files:
        path = os.path.join(NETMON_DIR, filename)
        assert os.path.exists(path), f"File {path} is missing."
        assert os.path.isfile(path), f"File {path} is not a regular file."


def test_prepared_file_contents():
    targets_path = os.path.join(NETMON_DIR, "targets.txt")
    with open(targets_path, "r") as f:
        assert f.read() == "127.0.0.1:8080\n127.0.0.1:8081\n127.0.0.1:9999\n"

    fallback_path = os.path.join(NETMON_DIR, "fallback_route.sh")
    with open(fallback_path, "r") as f:
        assert f.read().rstrip("\n") == 'echo "Executing fallback route"'


def test_ports_listening():
    """Verify that ports 8080 and 8081 are listening."""
    for port in [8080, 8081]:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            result = s.connect_ex(("127.0.0.1", port))
            assert result == 0, f"Port {port} is not listening."

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        assert s.connect_ex(("127.0.0.1", 9999)) != 0, "Port 9999 must not be listening."


def test_routing_json_content():
    """Verify the contents of routing.json."""
    routing_path = os.path.join(NETMON_DIR, "routing.json")
    with open(routing_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("routing.json is not valid JSON.")

    expected_data = {
        "127.0.0.1:8080": {"status": "UP", "priority": 1},
        "127.0.0.1:8081": {"status": "UP", "priority": 2},
        "127.0.0.1:9999": {"status": "DOWN", "priority": 3},
    }
    assert data == expected_data, f"routing.json content does not match expected. Got: {data}"


def test_connectivity_log_content():
    """Verify the contents of connectivity.log."""
    log_path = os.path.join(NETMON_DIR, "connectivity.log")
    with open(log_path, "r") as f:
        content = f.read()

    assert "Target 127.0.0.1:8080 -> UP" in content, "Missing or incorrect log entry for 8080."
    assert "Target 127.0.0.1:8081 -> UP" in content, "Missing or incorrect log entry for 8081."
    assert "Target 127.0.0.1:9999 -> DOWN" in content, "Missing or incorrect log entry for 9999."


def test_fallback_route_permissions():
    """Verify that fallback_route.sh has 700 permissions."""
    script_path = os.path.join(NETMON_DIR, "fallback_route.sh")
    perms = stat.S_IMODE(os.stat(script_path).st_mode)
    assert perms == 0o700, f"fallback_route.sh permissions should be 700, but got {oct(perms)}."


def test_cron_backup_content():
    """Verify that the cron backup file contains the correct cron expression."""
    cron_path = os.path.join(NETMON_DIR, "cron_backup.txt")
    with open(cron_path, "r") as f:
        content = f.read()

    cron_pattern = r'(?:\*/5|(?:[0-9]+,)*[0-9]+)\s+\*\s+\*\s+\*\s+\*.*monitor\.py'
    assert re.search(cron_pattern, content), "Cron backup does not contain the correct 5-minute schedule for monitor.py."


def _installed_crontabs():
    found = []
    for username in ("root", "user"):
        result = subprocess.run(
            ["crontab", "-u", username, "-l"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode == 0:
            found.append((username, result.stdout))
    return found


def test_cron_is_actually_installed_and_backed_up():
    schedule = r'(?:\*/5|0,5,10,15,20,25,30,35,40,45,50,55)'
    pattern = re.compile(
        rf'^\s*{schedule}\s+\*\s+\*\s+\*\s+\*\s+'
        r'/usr/bin/env\s+python3\s+/home/user/netmon/monitor\.py(?:\s+.*)?$',
        re.MULTILINE,
    )
    installed = _installed_crontabs()
    matching = [(name, text) for name, text in installed if pattern.search(text)]
    assert matching, "The required monitor job is not installed in a user crontab."

    backup = Path(NETMON_DIR, "cron_backup.txt").read_text()
    assert any(backup == text for _, text in matching), \
        "cron_backup.txt is not the output of the installed matching crontab."


def _make_listener(port=0):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", port))
    listener.listen(8)
    return listener, listener.getsockname()[1]


def _run_monitor(audit_dir, audit_file):
    env = os.environ.copy()
    env["PYTHONPATH"] = audit_dir
    env["NETMON_SOCKET_AUDIT"] = audit_file
    result = subprocess.run(
        ["/usr/bin/env", "python3", MONITOR],
        cwd="/tmp",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"monitor.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"


def test_monitor_behavior_on_derived_live_inputs():
    """Execute monitor.py and verify diagnostics, JSON, logging, timeout, and both ACL states."""
    targets_path = Path(NETMON_DIR, "targets.txt")
    routing_path = Path(NETMON_DIR, "routing.json")
    log_path = Path(NETMON_DIR, "connectivity.log")
    fallback_path = Path(NETMON_DIR, "fallback_route.sh")

    saved = {
        "targets": targets_path.read_bytes(),
        "routing": routing_path.read_bytes(),
        "log": log_path.read_bytes(),
        "fallback": fallback_path.read_bytes(),
        "mode": stat.S_IMODE(fallback_path.stat().st_mode),
    }

    up_listener = None
    failover_listener = None
    try:
        up_listener, up_port = _make_listener()
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.bind(("127.0.0.1", 0))
        down_port = probe.getsockname()[1]
        probe.close()
        assert down_port != up_port

        targets = [
            f"127.0.0.1:{up_port}",
            f"127.0.0.1:{down_port}",
            "127.0.0.1:9999",
        ]
        base_routing = {
            targets[0]: {"status": "unknown", "priority": 11},
            targets[1]: {"status": "unknown", "priority": 22},
            targets[2]: {"status": "unknown", "priority": 33},
        }
        targets_path.write_text("\n".join(targets) + "\n")
        routing_path.write_text(json.dumps(base_routing, indent=2) + "\n")
        log_path.write_text("")
        os.chmod(fallback_path, 0o600)

        with tempfile.TemporaryDirectory() as audit_dir:
            audit_file = os.path.join(audit_dir, "socket_calls.jsonl")
            Path(audit_dir, "sitecustomize.py").write_text(r'''
import json
import os
import socket

_real_socket = socket.socket
_real_create_connection = socket.create_connection
_real_setdefaulttimeout = socket.setdefaulttimeout
_audit = os.environ.get("NETMON_SOCKET_AUDIT")

def _record(value):
    if _audit:
        with open(_audit, "a") as f:
            f.write(json.dumps(value) + "\n")

class TrackingSocket:
    def __init__(self, *args, **kwargs):
        self._socket = _real_socket(*args, **kwargs)
    def settimeout(self, value):
        _record(value)
        return self._socket.settimeout(value)
    def __getattr__(self, name):
        return getattr(self._socket, name)
    def __enter__(self):
        return self
    def __exit__(self, exc_type, exc, tb):
        self._socket.close()
        return False

def create_connection(address, timeout=socket._GLOBAL_DEFAULT_TIMEOUT, source_address=None, all_errors=False):
    if timeout is not socket._GLOBAL_DEFAULT_TIMEOUT:
        _record(timeout)
    return _real_create_connection(address, timeout, source_address, all_errors=all_errors)

def setdefaulttimeout(value):
    _record(value)
    return _real_setdefaulttimeout(value)

socket.socket = TrackingSocket
socket.create_connection = create_connection
socket.setdefaulttimeout = setdefaulttimeout
''')

            _run_monitor(audit_dir, audit_file)

            expected_down = {
                targets[0]: {"status": "UP", "priority": 11},
                targets[1]: {"status": "DOWN", "priority": 22},
                targets[2]: {"status": "DOWN", "priority": 33},
            }
            assert json.loads(routing_path.read_text()) == expected_down
            assert routing_path.read_text().rstrip("\n") == json.dumps(expected_down, indent=2)
            first_lines = [
                f"Target {targets[0]} -> UP",
                f"Target {targets[1]} -> DOWN",
                "Target 127.0.0.1:9999 -> DOWN",
            ]
            assert log_path.read_text() == "\n".join(first_lines) + "\n"
            assert stat.S_IMODE(fallback_path.stat().st_mode) == 0o700

            failover_listener, _ = _make_listener(9999)
            _run_monitor(audit_dir, audit_file)

            expected_up = {
                targets[0]: {"status": "UP", "priority": 11},
                targets[1]: {"status": "DOWN", "priority": 22},
                targets[2]: {"status": "UP", "priority": 33},
            }
            assert json.loads(routing_path.read_text()) == expected_up
            assert routing_path.read_text().rstrip("\n") == json.dumps(expected_up, indent=2)
            second_lines = [
                f"Target {targets[0]} -> UP",
                f"Target {targets[1]} -> DOWN",
                "Target 127.0.0.1:9999 -> UP",
            ]
            assert log_path.read_text() == "\n".join(first_lines + second_lines) + "\n"
            assert stat.S_IMODE(fallback_path.stat().st_mode) == 0o600

            assert os.path.exists(audit_file), "monitor.py did not use the socket module."
            recorded = [json.loads(line) for line in Path(audit_file).read_text().splitlines()]
            assert any(isinstance(value, (int, float)) and not isinstance(value, bool) and value == 1 for value in recorded), \
                "No socket operation configured the required 1-second timeout."
    finally:
        if failover_listener is not None:
            failover_listener.close()
        if up_listener is not None:
            up_listener.close()
        targets_path.write_bytes(saved["targets"])
        routing_path.write_bytes(saved["routing"])
        log_path.write_bytes(saved["log"])
        fallback_path.write_bytes(saved["fallback"])
        os.chmod(fallback_path, saved["mode"])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
