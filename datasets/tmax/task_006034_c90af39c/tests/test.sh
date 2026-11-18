#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import re
import shlex
import subprocess
import time
import urllib.request

import pytest

CONF = "/home/user/app/supervisord.conf"
SOCKET = "/home/user/app/supervisor.sock"


def test_symlink_active_data():
    """Verify /home/user/app/active_data is a symlink pointing to /home/user/app/data."""
    symlink_path = "/home/user/app/active_data"
    expected_target = "/home/user/app/data"

    assert os.path.isdir("/home/user/app/data"), "/home/user/app/data is missing."
    assert os.path.isdir("/home/user/app/logs"), "/home/user/app/logs is missing."
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink or does not exist."

    target = os.readlink(symlink_path)
    abs_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    assert abs_target == expected_target, f"Symlink points to {abs_target}, expected {expected_target}."


def test_service_b_port_fixed():
    """Verify service_b.py has been modified to use port 8000."""
    service_b_path = "/home/user/src/service_b.py"
    assert os.path.isfile(service_b_path), f"{service_b_path} does not exist."

    with open(service_b_path, "r") as f:
        content = f.read()

    assert "127.0.0.1:8000" in content, "service_b.py does not contain the corrected port 8000."
    assert "127.0.0.1:9090" not in content, "service_b.py still contains the misconfigured port 9090."


def load_config():
    assert os.path.isfile(CONF), f"{CONF} does not exist."
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(CONF)
    return cfg


def test_supervisord_configuration():
    """Verify the requested supervisor sections and service settings."""
    cfg = load_config()
    required = [
        "supervisord", "program:service_a", "program:service_b",
        "unix_http_server", "rpcinterface:supervisor", "supervisorctl",
    ]
    for section in required:
        assert cfg.has_section(section), f"Missing [{section}] section in {CONF}."

    assert cfg.getboolean("supervisord", "nodaemon") is False
    assert cfg.get("supervisord", "logfile") == "/home/user/app/logs/supervisord.log"
    assert cfg.get("supervisord", "pidfile") == "/home/user/app/supervisord.pid"

    expected = {
        "program:service_a": {
            "command": ["python3", "/home/user/src/service_a.py"],
            "stdout_logfile": "/home/user/app/logs/service_a.log",
            "stderr_logfile": "/home/user/app/logs/service_a.err",
        },
        "program:service_b": {
            "command": ["python3", "/home/user/src/service_b.py"],
            "stdout_logfile": "/home/user/app/logs/service_b.log",
            "stderr_logfile": "/home/user/app/logs/service_b.err",
        },
    }
    for section, values in expected.items():
        assert shlex.split(cfg.get(section, "command")) == values["command"]
        assert cfg.getboolean(section, "autorestart") is True
        assert cfg.get(section, "stdout_logfile") == values["stdout_logfile"]
        assert cfg.get(section, "stderr_logfile") == values["stderr_logfile"]

    assert cfg.get("unix_http_server", "file") == SOCKET
    assert cfg.get("supervisorctl", "serverurl") == "unix:///home/user/app/supervisor.sock"
    assert cfg.has_option("rpcinterface:supervisor", "supervisor.rpcinterface_factory")


def test_supervisord_running():
    """Verify supervisord is running (original assertion)."""
    try:
        output = subprocess.check_output(["pgrep", "-f", "supervisord"]).decode("utf-8").strip()
        assert output, "supervisord process not found."
    except subprocess.CalledProcessError:
        pytest.fail("supervisord is not running.")


def proc_cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]


def proc_parent(pid):
    with open(f"/proc/{pid}/status", "r") as f:
        for line in f:
            if line.startswith("PPid:"):
                return int(line.split()[1])
    raise AssertionError(f"Could not determine parent of PID {pid}")


def supervisor_status():
    result = subprocess.run(
        ["supervisorctl", "-c", CONF, "status"],
        text=True, capture_output=True, timeout=5,
    )
    assert result.returncode == 0, f"supervisorctl failed: {result.stdout} {result.stderr}"
    statuses = {}
    for line in result.stdout.splitlines():
        match = re.match(r"^(service_[ab])\s+(\S+)(?:\s+pid\s+(\d+),)?", line.strip())
        if match:
            statuses[match.group(1)] = (match.group(2), int(match.group(3)) if match.group(3) else None)
    return statuses


def test_services_are_actually_supervised():
    """Verify this configuration's real supervisord owns both running services."""
    pidfile = "/home/user/app/supervisord.pid"
    assert os.path.isfile(pidfile), "Configured supervisord pidfile is missing."
    with open(pidfile) as f:
        supervisor_pid = int(f.read().strip())

    supervisor_cmd = proc_cmdline(supervisor_pid)
    joined = " ".join(supervisor_cmd)
    assert "supervisord" in joined, f"PID {supervisor_pid} is not supervisord: {joined}"
    assert CONF in supervisor_cmd, f"Supervisord was not started with {CONF}: {joined}"
    assert os.path.exists(SOCKET), "Configured supervisor control socket is missing."

    deadline = time.time() + 6
    statuses = {}
    while time.time() < deadline:
        statuses = supervisor_status()
        if all(statuses.get(name, (None,))[0] == "RUNNING" for name in ("service_a", "service_b")):
            break
        time.sleep(0.5)

    for name, script in (("service_a", "/home/user/src/service_a.py"),
                         ("service_b", "/home/user/src/service_b.py")):
        assert name in statuses, f"{name} is not registered with supervisor."
        state, pid = statuses[name]
        assert state == "RUNNING", f"{name} is not RUNNING (state={state})."
        assert pid is not None and os.path.exists(f"/proc/{pid}"), f"{name} has no live PID."
        assert script in proc_cmdline(pid), f"{name} PID {pid} is not running {script}."
        assert proc_parent(pid) == supervisor_pid, f"{name} is not a child of the configured supervisord."


def test_pipeline_success_file():
    """Verify pipeline_success.json exists and contains the correct data."""
    success_file_path = "/home/user/app/data/pipeline_success.json"
    assert os.path.isfile(success_file_path), f"Success file {success_file_path} is missing. Network issue not fixed or services not running properly."

    with open(success_file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {success_file_path} does not contain valid JSON.")

    assert data.get("result") == "success", "JSON 'result' is not 'success'."
    assert data.get("source") == "pipeline_ready", "JSON 'source' is not 'pipeline_ready'."


def test_pipeline_recreates_output_from_live_provider():
    """Remove the artifact and require the supervised pipeline to recreate it."""
    success_file_path = "/home/user/app/data/pipeline_success.json"
    if os.path.lexists(success_file_path):
        os.unlink(success_file_path)

    with urllib.request.urlopen("http://127.0.0.1:8000/", timeout=3) as response:
        provider_data = json.loads(response.read().decode())
    assert provider_data.get("status") == "ok"

    deadline = time.time() + 8
    produced = None
    while time.time() < deadline:
        try:
            with open(success_file_path, "r") as f:
                produced = json.load(f)
            break
        except (FileNotFoundError, json.JSONDecodeError):
            time.sleep(0.25)

    assert produced is not None, "The running consumer did not recreate pipeline_success.json."
    assert produced.get("result") == "success"
    assert produced.get("source") == provider_data.get("payload"), \
        "Consumer output was not derived from the live provider response."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
