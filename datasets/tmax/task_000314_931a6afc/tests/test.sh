#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

import pytest

ENV_PATH = Path("/home/user/app/.env")
REPORT_PATH = Path("/home/user/diagnostic_report.json")
FRONTEND_LOG = Path("/home/user/logs/frontend.log")
BACKEND_LOG = Path("/home/user/logs/backend.log")
TOOLS_ROOT = Path("/home/user/tools")
PREFERRED_PROJECT = TOOLS_ROOT / "log_analyzer"


def rust_command():
    """Find a submitted Rust analyzer and return a command that builds/runs it."""
    manifests = []
    if PREFERRED_PROJECT.is_dir() and (PREFERRED_PROJECT / "Cargo.toml").is_file():
        manifests.append(PREFERRED_PROJECT / "Cargo.toml")
    if TOOLS_ROOT.is_dir():
        manifests.extend(
            p for p in TOOLS_ROOT.rglob("Cargo.toml")
            if p not in manifests and "target" not in p.parts
        )

    if manifests:
        manifest = manifests[0]
        return ["cargo", "run", "--quiet", "--manifest-path", str(manifest)], manifest.parent

    candidates = []
    if PREFERRED_PROJECT.is_file():
        candidates.append(PREFERRED_PROJECT)
    if PREFERRED_PROJECT.is_dir():
        candidates.extend(
            p for p in PREFERRED_PROJECT.rglob("*.rs") if "target" not in p.parts
        )
    if TOOLS_ROOT.is_dir():
        candidates.extend(
            p for p in TOOLS_ROOT.rglob("*.rs")
            if p not in candidates and "target" not in p.parts
        )

    for source in candidates:
        try:
            text = source.read_text(errors="replace")
        except OSError:
            continue
        if re.search(r"\bfn\s+main\s*\(", text):
            executable = Path("/tmp/submitted_log_analyzer")
            subprocess.run(
                ["rustc", str(source), "-o", str(executable)],
                check=True,
                timeout=120,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            return [str(executable)], source.parent

    pytest.fail("No runnable Rust log analyzer source or Cargo project was found under /home/user/tools")


def run_analyzer(command, cwd):
    if REPORT_PATH.exists():
        REPORT_PATH.unlink()
    subprocess.run(
        command,
        cwd=str(cwd),
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert REPORT_PATH.is_file(), "The Rust analyzer did not generate /home/user/diagnostic_report.json"


def expected_from_logs(logs):
    pattern = re.compile(r"^\[([^\]]+)\]\s+\S+\s+\[REQ-008\]\s(.*)$")
    events = []
    for service, content in logs:
        for line in content.splitlines():
            match = pattern.match(line)
            if match:
                timestamp, message = match.groups()
                events.append({
                    "service": service,
                    "timestamp": timestamp,
                    "message": message.strip(),
                })
    events.sort(key=lambda event: datetime.strptime(event["timestamp"], "%Y-%m-%dT%H:%M:%S.%fZ"))
    return events


def test_env_file_updated_and_value_converted():
    assert ENV_PATH.is_file(), f"File {ENV_PATH} is missing"
    content = ENV_PATH.read_text()

    assert "API_TIMEOUT_MS" in content, "The .env file must contain the corrected key 'API_TIMEOUT_MS'"
    assert "API_TIMEOUT_S" not in content, "The .env file should no longer contain the incorrect key 'API_TIMEOUT_S'"

    values = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() == "API_TIMEOUT_MS":
            values.append(value.strip())

    assert values == ["30000"], "API_TIMEOUT_MS must be the numeric millisecond conversion of 30 seconds: 30000"


def test_rust_analyzer_processes_changed_logs_and_regenerates_report():
    command, cwd = rust_command()
    original_frontend = FRONTEND_LOG.read_text()
    original_backend = BACKEND_LOG.read_text()

    probe_frontend = """[2025-02-03T08:00:04.900Z] INFO [REQ-008] Frontend finished probe   
[2025-02-03T08:00:00.001Z] INFO [REQ-777] Unrelated frontend request
[2025-02-03T08:00:01.020Z] INFO [REQ-008] Frontend began probe
"""
    probe_backend = """[2025-02-03T08:00:03.400Z] ERROR [REQ-008] Backend probe failed
[2025-02-03T08:00:02.300Z] INFO [REQ-008] Backend accepted probe
[2025-02-03T08:00:00.100Z] INFO [REQ-009] Unrelated backend request
"""
    expected = expected_from_logs([
        ("frontend", probe_frontend),
        ("backend", probe_backend),
    ])

    try:
        FRONTEND_LOG.write_text(probe_frontend)
        BACKEND_LOG.write_text(probe_backend)
        run_analyzer(command, cwd)

        with REPORT_PATH.open() as report_file:
            data = json.load(report_file)

        assert data.get("misconfigured_key") == "API_TIMEOUT_S"
        assert str(data.get("corrected_value")) == "30000"
        assert data.get("timeline") == expected, "Analyzer did not derive the timeline from the current log contents"
    finally:
        FRONTEND_LOG.write_text(original_frontend)
        BACKEND_LOG.write_text(original_backend)
        run_analyzer(command, cwd)


def test_diagnostic_report_exists_and_valid():
    assert REPORT_PATH.is_file(), f"Diagnostic report {REPORT_PATH} was not generated"

    with REPORT_PATH.open() as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON")

    assert "misconfigured_key" in data, "JSON missing 'misconfigured_key'"
    assert "corrected_value" in data, "JSON missing 'corrected_value'"
    assert "timeline" in data, "JSON missing 'timeline'"


def test_diagnostic_report_contents():
    assert REPORT_PATH.is_file(), "Report not found"
    with REPORT_PATH.open() as f:
        data = json.load(f)

    assert data["misconfigured_key"] == "API_TIMEOUT_S", "misconfigured_key should be 'API_TIMEOUT_S'"

    env_val = None
    if ENV_PATH.is_file():
        with ENV_PATH.open() as f:
            for line in f:
                if line.startswith("API_TIMEOUT_MS="):
                    env_val = line.strip().split("=", 1)[1]

    if env_val:
        assert str(data["corrected_value"]) == env_val, "corrected_value in JSON does not match the value in .env"


def test_diagnostic_report_timeline():
    assert REPORT_PATH.is_file(), "Report not found"
    with REPORT_PATH.open() as f:
        data = json.load(f)

    timeline = data.get("timeline", [])
    assert len(timeline) == 6, f"Expected 6 events for REQ-008, found {len(timeline)}"

    expected_events = [
        {"service": "frontend", "timestamp": "2023-10-01T10:05:01.000Z", "message": "Received request from client"},
        {"service": "frontend", "timestamp": "2023-10-01T10:05:01.010Z", "message": "Forwarding to backend"},
        {"service": "backend", "timestamp": "2023-10-01T10:05:01.015Z", "message": "Backend received payload"},
        {"service": "backend", "timestamp": "2023-10-01T10:05:01.035Z", "message": "Database query started"},
        {"service": "frontend", "timestamp": "2023-10-01T10:05:01.040Z", "message": "Timeout exceeded while waiting for backend"},
        {"service": "backend", "timestamp": "2023-10-01T10:05:01.200Z", "message": "Database query finished"},
    ]

    for i, (actual, expected) in enumerate(zip(timeline, expected_events)):
        assert actual.get("service") == expected["service"], f"Event {i} service mismatch"
        assert actual.get("timestamp") == expected["timestamp"], f"Event {i} timestamp mismatch (possibly not sorted chronologically)"
        assert actual.get("message") == expected["message"], f"Event {i} message mismatch"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
