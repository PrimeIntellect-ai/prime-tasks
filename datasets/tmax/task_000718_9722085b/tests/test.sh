#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

import pytest


def _proc_is_live_python_script(pid, script_path):
    proc = Path(f"/proc/{pid}")
    try:
        state = (proc / "stat").read_text().split()[2]
        cmdline = (proc / "cmdline").read_bytes().split(b"\0")
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return False
    return state != "Z" and os.fsencode(script_path) in cmdline


def _read_events(path, token):
    events = []
    try:
        lines = Path(path).read_text().splitlines()
    except FileNotFoundError:
        return events
    for line in lines:
        parts = line.split("|")
        if len(parts) == 4 and parts[0] == token:
            try:
                events.append((parts[1], int(parts[2]), int(parts[3])))
            except ValueError:
                pass
    return events


def test_services_running_and_correctly_sequenced():
    """Execute start_all.sh with instrumented real service paths and verify ordering and liveness."""
    service_dir = Path("/home/user/services")
    script_path = service_dir / "start_all.sh"
    app_path = service_dir / "app_server.py"
    analyzer_path = service_dir / "cost_analyzer.py"
    symlink_path = Path("/home/user/app_data/active_data")

    assert script_path.is_file(), f"Missing {script_path}"
    assert app_path.is_file(), f"Missing {app_path}"
    assert analyzer_path.is_file(), f"Missing {analyzer_path}"

    subprocess.run(["pkill", "-f", "python3 /home/user/services/app_server.py"], capture_output=True)
    subprocess.run(["pkill", "-f", "python3 /home/user/services/cost_analyzer.py"], capture_output=True)
    if os.path.lexists(symlink_path):
        symlink_path.unlink()

    token = uuid.uuid4().hex
    marker_dir = Path(tempfile.mkdtemp(prefix="service_probe_"))
    app_log = marker_dir / "app.events"
    analyzer_log = marker_dir / "analyzer.events"

    app_original = app_path.read_bytes()
    analyzer_original = analyzer_path.read_bytes()
    app_mode = app_path.stat().st_mode
    analyzer_mode = analyzer_path.stat().st_mode
    launcher = None

    app_probe = '''import os
import time

TOKEN = os.environ["SERVICE_TEST_TOKEN"]
LOG = os.environ["APP_TEST_LOG"]
LINK = "/home/user/app_data/active_data"
TARGET = "/home/user/app_data/v1"

def log(event, timestamp=None):
    if timestamp is None:
        timestamp = time.monotonic_ns()
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f"{TOKEN}|{event}|{timestamp}|{os.getpid()}\\n")
        f.flush()
        os.fsync(f.fileno())

log("app_start")
time.sleep(1.5)
os.makedirs(TARGET, exist_ok=True)
if os.path.lexists(LINK):
    os.unlink(LINK)
ready_threshold = time.monotonic_ns()
os.symlink(TARGET, LINK)
log("ready", ready_threshold)
while True:
    time.sleep(0.2)
'''

    analyzer_probe = '''import os
import sys
import time

TOKEN = os.environ["SERVICE_TEST_TOKEN"]
LOG = os.environ["ANALYZER_TEST_LOG"]
LINK = "/home/user/app_data/active_data"

def log(event):
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f"{TOKEN}|{event}|{time.monotonic_ns()}|{os.getpid()}\\n")
        f.flush()
        os.fsync(f.fileno())

log("analyzer_start")
if not os.path.islink(LINK) or not os.path.exists(LINK):
    sys.exit(42)
while True:
    time.sleep(0.2)
'''

    try:
        app_path.write_text(app_probe)
        analyzer_path.write_text(analyzer_probe)
        os.chmod(app_path, 0o755)
        os.chmod(analyzer_path, 0o755)

        env = os.environ.copy()
        env.update({
            "SERVICE_TEST_TOKEN": token,
            "APP_TEST_LOG": str(app_log),
            "ANALYZER_TEST_LOG": str(analyzer_log),
        })
        launcher = subprocess.Popen(
            ["bash", str(script_path)],
            cwd=str(service_dir),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        deadline = time.monotonic() + 8
        events_app = []
        events_analyzer = []
        while time.monotonic() < deadline:
            events_app = _read_events(app_log, token)
            events_analyzer = _read_events(analyzer_log, token)
            if any(e[0] == "ready" for e in events_app) and events_analyzer:
                break
            time.sleep(0.05)

        app_starts = [e for e in events_app if e[0] == "app_start"]
        ready_events = [e for e in events_app if e[0] == "ready"]
        analyzer_starts = [e for e in events_analyzer if e[0] == "analyzer_start"]

        assert app_starts, "start_all.sh did not execute app_server.py"
        assert ready_events, "app_server.py did not create the active_data symlink"
        assert analyzer_starts, "start_all.sh did not execute cost_analyzer.py"
        assert symlink_path.is_symlink(), "active_data was not created as a symlink"

        ready_time = min(e[1] for e in ready_events)
        assert min(e[1] for e in analyzer_starts) >= ready_time, (
            "cost_analyzer.py was started before app_server.py created active_data"
        )

        time.sleep(1)
        assert any(_proc_is_live_python_script(e[2], str(app_path)) for e in app_starts), (
            "app_server.py is not running in the background. It may have crashed or was not started."
        )
        assert any(_proc_is_live_python_script(e[2], str(analyzer_path)) for e in analyzer_starts), (
            "cost_analyzer.py is not running in the background. It likely crashed because it started before the active_data symlink was created."
        )
    finally:
        if launcher is not None:
            try:
                os.killpg(launcher.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for event_file in (app_log, analyzer_log):
            for event in _read_events(event_file, token):
                try:
                    os.kill(event[2], signal.SIGTERM)
                except ProcessLookupError:
                    pass
        app_path.write_bytes(app_original)
        analyzer_path.write_bytes(analyzer_original)
        os.chmod(app_path, app_mode)
        os.chmod(analyzer_path, analyzer_mode)
        if os.path.lexists(symlink_path):
            symlink_path.unlink()


def _run_classifier(script_path, filepath, expected, as_user=False):
    command = ["python3", script_path, filepath]
    if as_user:
        command = ["runuser", "-u", "user", "--"] + command
    result = subprocess.run(command, capture_output=True, text=True, timeout=4)
    assert result.returncode == 0, f"Classifier failed for {filepath}: {result.stderr}"
    assert result.stdout.strip() == expected, (
        f"Classifier returned {result.stdout!r} for {filepath}; expected {expected}"
    )


def test_classifier_script_original_corpus():
    """Retain the original clean and evil corpus assertions."""
    script_path = "/home/user/classifier.py"
    assert os.path.isfile(script_path), f"Classifier script missing at {script_path}"

    evil_dir = "/home/user/corpus/evil/"
    clean_dir = "/home/user/corpus/clean/"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run(["python3", script_path, filepath], capture_output=True, text=True, timeout=4)
        if result.stdout.strip() != "DELETE":
            evil_bypassed.append(filename)
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        result = subprocess.run(["python3", script_path, filepath], capture_output=True, text=True, timeout=4)
        if result.stdout.strip() != "KEEP":
            clean_modified.append(filename)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_classifier_randomized_rule_cases():
    """Exercise every rule on unpredictable paths outside the fixed corpus."""
    script_path = "/home/user/classifier.py"
    assert os.path.isfile(script_path), f"Classifier script missing at {script_path}"

    case_dir = Path(tempfile.mkdtemp(prefix=f"storage_cases_{uuid.uuid4().hex}_"))
    os.chmod(case_dir, 0o755)

    cases = [
        (".tmp", "[ACTIVE] extension precedence\n", "DELETE"),
        (".bak", "[ACTIVE] extension precedence\n", "DELETE"),
        (".config", "[ORPHANED] config precedence\n", "KEEP"),
        (".dat", "[ORPHANED] forgotten\n", "DELETE"),
        (".log", "[ORPHANED]extra text\n", "DELETE"),
        (".bin", "[ACTIVE] current\n", "KEEP"),
        (".txt", "ordinary content\n", "KEEP"),
        (".data", " [ORPHANED] leading space is not strict\n", "KEEP"),
        (".blob", "[orphaned] wrong case\n", "KEEP"),
        (".empty", "", "KEEP"),
    ]

    for suffix, content, expected in cases:
        path = case_dir / f"{uuid.uuid4().hex}{suffix}"
        path.write_text(content)
        os.chmod(path, 0o644)
        _run_classifier(script_path, str(path), expected, as_user=True)

    unreadable = case_dir / f"{uuid.uuid4().hex}.raw"
    unreadable.write_text("[ORPHANED] unreadable must default to keep\n")
    os.chmod(unreadable, 0)
    _run_classifier(script_path, str(unreadable), "KEEP", as_user=True)

    missing = case_dir / f"{uuid.uuid4().hex}.missing"
    _run_classifier(script_path, str(missing), "KEEP", as_user=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
