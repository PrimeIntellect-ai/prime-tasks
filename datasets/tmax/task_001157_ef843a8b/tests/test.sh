#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import socket
import subprocess
import time
from pathlib import Path

import pytest

BINARY = "/home/user/capacity_monitor/target/release/capacity_monitor"
PROJECT = "/home/user/capacity_monitor"
LOG_FILE = "/home/user/capacity_log.jsonl"
EXPECTED_KEYS = {
    "timestamp",
    "load_1m",
    "mem_avail_kb",
    "endpoint_reachable",
    "threshold_exceeded",
}


def test_bashrc_env_vars():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"{bashrc_path} does not exist"

    with open(bashrc_path, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "METRICS_HOST" in content and "127.0.0.1:9999" in content, "METRICS_HOST not correctly exported in .bashrc"
    assert "export METRICS_HOST" in content, "METRICS_HOST is not exported"
    assert "LOAD_THRESHOLD" in content and "4.0" in content, "LOAD_THRESHOLD not correctly exported in .bashrc"
    assert "export LOAD_THRESHOLD" in content, "LOAD_THRESHOLD is not exported"

    # The requested exports must be the effective final non-empty commands.
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) >= 2, ".bashrc does not end with both exports"
    assert re.fullmatch(r"export\s+METRICS_HOST\s*=\s*(['\"]?)127\.0\.0\.1:9999\1", lines[-2]), "METRICS_HOST export is not the penultimate effective line"
    assert re.fullmatch(r"export\s+LOAD_THRESHOLD\s*=\s*(['\"]?)4\.0\1", lines[-1]), "LOAD_THRESHOLD export is not the final effective line"

    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", f"source {bashrc_path}; printf '%s\\n%s' \"$METRICS_HOST\" \"$LOAD_THRESHOLD\""],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f".bashrc cannot be sourced: {result.stderr}"
    assert result.stdout.splitlines() == ["127.0.0.1:9999", "4.0"], "exported environment values are not effective"


def _active_cron_entries(text):
    return [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]


def _has_effective_schedule(entries):
    expected_command = BINARY
    for line in entries:
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[:5] == ["*/5", "*", "*", "*", "*"]:
            command = fields[5].strip()
            if command == expected_command or re.fullmatch(r"(?:[A-Za-z_][A-Za-z0-9_]*=[^\s]+\s+)*" + re.escape(expected_command), command):
                return True
    return False


def test_crontab_configured():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab"

    crontab_output = result.stdout
    expected_command = BINARY
    # Preserve the original checks.
    assert expected_command in crontab_output, f"Crontab does not contain the expected command: {expected_command}"
    assert "*/5 * * * *" in crontab_output, "Crontab does not schedule the task every 5 minutes"

    planner = Path("/home/user/planner.cron")
    assert planner.is_file(), "/home/user/planner.cron does not exist"
    planner_entries = _active_cron_entries(planner.read_text())
    installed_entries = _active_cron_entries(crontab_output)
    assert _has_effective_schedule(planner_entries), "planner.cron does not effectively run the release binary every 5 minutes"
    assert _has_effective_schedule(installed_entries), "installed crontab does not effectively run the release binary every 5 minutes"
    assert planner_entries == installed_entries, "planner.cron was not loaded as the installed crontab"


def test_rust_binary_exists_and_executable():
    assert os.path.exists(BINARY), f"Rust binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Rust binary at {BINARY} is not executable"

    cargo_toml = Path(PROJECT) / "Cargo.toml"
    source = Path(PROJECT) / "src/main.rs"
    assert cargo_toml.is_file(), "Cargo.toml is missing"
    assert source.is_file(), "src/main.rs is missing"

    source_text = source.read_text()
    for required in ["/proc/loadavg", "/proc/meminfo", "MemAvailable", "METRICS_HOST", "LOAD_THRESHOLD", "capacity_log.jsonl"]:
        assert required in source_text, f"Rust source does not reference {required}"
    assert "TcpStream" in source_text and "connect_timeout" in source_text, "Rust source does not use a timed TCP connection"
    assert re.search(r"from_secs\s*\(\s*2\s*\)", source_text), "TCP timeout is not configured as 2 seconds"

    # Rebuild the submitted Rust project in release mode so the exercised artifact
    # must be the release output produced from the submitted Cargo project.
    build = subprocess.run(
        ["cargo", "build", "--release", "--offline"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build.returncode == 0, f"cargo build --release failed:\n{build.stdout}\n{build.stderr}"
    assert Path(BINARY).read_bytes()[:4] == b"\x7fELF", "release artifact is not an ELF binary"


def _proc_values():
    with open("/proc/loadavg") as f:
        load = float(f.read().split()[0])
    mem = None
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemAvailable:"):
                mem = int(line.split()[1])
                break
    assert mem is not None, "MemAvailable is absent from /proc/meminfo"
    return load, mem


def _run_and_read_one(host, threshold):
    initial_lines = []
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE) as f:
            initial_lines = f.readlines()

    before_load, before_mem = _proc_values()
    started = int(time.time())
    env = os.environ.copy()
    env["METRICS_HOST"] = host
    env["LOAD_THRESHOLD"] = str(threshold)
    result = subprocess.run([BINARY], env=env, capture_output=True, text=True, timeout=5)
    finished = int(time.time())
    after_load, after_mem = _proc_values()

    assert result.returncode == 0, f"Binary execution failed with output: {result.stderr}"
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} was not created"
    with open(LOG_FILE) as f:
        lines = f.readlines()

    # Preserve the original append assertion, then require exactly one appended line.
    assert len(lines) > len(initial_lines), "Binary did not append a new line to the log file"
    assert len(lines) == len(initial_lines) + 1, "Each execution must append exactly one JSON line"

    last_line = lines[-1].strip()
    try:
        data = json.loads(last_line)
    except json.JSONDecodeError:
        pytest.fail(f"Appended line is not valid JSON: {last_line}")

    assert set(data.keys()) == EXPECTED_KEYS, f"JSON object missing or has extra keys. Expected {EXPECTED_KEYS}, got {set(data.keys())}"
    assert isinstance(data["timestamp"], int), "timestamp must be an integer"
    assert isinstance(data["load_1m"], float), "load_1m must be a float"
    assert isinstance(data["mem_avail_kb"], int), "mem_avail_kb must be an integer"
    assert isinstance(data["endpoint_reachable"], bool), "endpoint_reachable must be a boolean"
    assert isinstance(data["threshold_exceeded"], bool), "threshold_exceeded must be a boolean"
    assert type(data["timestamp"]) is int and type(data["mem_avail_kb"]) is int, "integer fields cannot be booleans"

    assert data["threshold_exceeded"] == (data["load_1m"] > threshold), "threshold_exceeded logic is incorrect"
    current_time = int(time.time())
    assert abs(current_time - data["timestamp"]) < 10, "timestamp is not close to current time"
    assert started - 1 <= data["timestamp"] <= finished + 1, "timestamp was not recorded during execution"

    # Values must match the live /proc readings bracketing execution.
    assert min(before_load, after_load) - 0.02 <= data["load_1m"] <= max(before_load, after_load) + 0.02, "load_1m does not match /proc/loadavg"
    assert min(before_mem, after_mem) - 65536 <= data["mem_avail_kb"] <= max(before_mem, after_mem) + 65536, "mem_avail_kb does not match /proc/meminfo"
    return data


def test_rust_binary_execution_and_log():
    # Reachable endpoint: keep a real listening socket open while the binary runs.
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    port = listener.getsockname()[1]
    try:
        reachable = _run_and_read_one(f"127.0.0.1:{port}", -1.0)
    finally:
        listener.close()
    assert reachable["endpoint_reachable"] is True, "successful TCP connectivity was not detected"
    assert reachable["threshold_exceeded"] is True, "LOAD_THRESHOLD was not read for the true case"

    # Reserve and release another local port, which should reject connections.
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    closed_port = probe.getsockname()[1]
    probe.close()
    unreachable = _run_and_read_one(f"127.0.0.1:{closed_port}", 1e100)
    assert unreachable["endpoint_reachable"] is False, "failed TCP connectivity was not detected"
    assert unreachable["threshold_exceeded"] is False, "LOAD_THRESHOLD was not read for the false case"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
