#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import threading
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

UNIT_FILE = "/home/user/systemd/user/monitor.service"
SOURCE = "/home/user/monitor.c"
BINARY = "/home/user/monitor"
LOG_FILE = "/home/user/monitor.log"
TOKYO = ZoneInfo("Asia/Tokyo")


def test_systemd_unit_file():
    """Verify the systemd unit file is correctly configured."""
    assert os.path.isfile(UNIT_FILE), f"Systemd unit file {UNIT_FILE} does not exist."

    with open(UNIT_FILE, "r") as f:
        content = f.read()

    # Preserve the original unit assertions.
    assert re.search(r"^Type\s*=\s*oneshot", content, re.MULTILINE | re.IGNORECASE), \
        f"{UNIT_FILE} is missing 'Type=oneshot'."
    assert re.search(r"^After\s*=.*target-server\.service", content, re.MULTILINE | re.IGNORECASE), \
        f"{UNIT_FILE} is missing 'After=target-server.service'."
    assert re.search(r"^Environment\s*=.*TZ=Asia/Tokyo", content, re.MULTILINE | re.IGNORECASE), \
        f"{UNIT_FILE} is missing 'Environment=TZ=Asia/Tokyo' (or similar)."

    # The oneshot must execute the requested artifact.
    assert re.search(r"^ExecStart\s*=\s*/home/user/monitor(?:\s|$)", content,
                     re.MULTILINE | re.IGNORECASE), \
        f"{UNIT_FILE} is missing 'ExecStart=/home/user/monitor'."


def test_c_source_and_binary():
    """Verify the C source and compiled executable exist and are the right kind."""
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary."


def test_monitor_log():
    """Preserve the original proof-of-success log assertion."""
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist."
    with open(LOG_FILE, "r") as f:
        content = f.read()

    pattern = r"^OK:\s*\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}"
    assert re.search(pattern, content, re.MULTILINE), \
        f"{LOG_FILE} does not contain a successful 'OK: YYYY-MM-DD HH:MM:SS' entry."


def assert_one_run(binary, expected_status, listener=False):
    sentinel = "verifier-sentinel"
    with open(LOG_FILE, "w") as f:
        f.write(sentinel + "\n")

    server = None
    accepted = threading.Event()
    thread = None
    if listener:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 8080))
        server.listen(4)
        server.settimeout(5)

        def accept_connection():
            try:
                conn, _ = server.accept()
                accepted.set()
                conn.close()
            except OSError:
                pass

        thread = threading.Thread(target=accept_connection, daemon=True)
        thread.start()
    else:
        # Establish that the required endpoint is currently unbound, so this is
        # a real connection-failure test rather than a trusted log inspection.
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind(("127.0.0.1", 8080))
        except OSError as exc:
            pytest.fail(f"Port 8080 unexpectedly occupied during failure test: {exc}")
        finally:
            probe.close()

    env = os.environ.copy()
    env["TZ"] = "Asia/Tokyo"
    before = datetime.now(TOKYO)
    try:
        result = subprocess.run([binary], env=env, timeout=10,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    finally:
        after = datetime.now(TOKYO)
        if listener:
            if thread is not None:
                thread.join(timeout=5)
            server.close()

    assert result.returncode == 0, \
        f"{binary} exited with {result.returncode}; stderr={result.stderr.decode(errors='replace')}"
    if listener:
        assert accepted.is_set(), f"{binary} did not connect to 127.0.0.1:8080"

    with open(LOG_FILE, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 2 and lines[0] == sentinel, \
        f"{binary} must append exactly one result line without replacing existing log content: {lines!r}"

    match = re.fullmatch(
        rf"{expected_status}: (\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})",
        lines[1],
    )
    assert match, f"Unexpected monitor log line: {lines[1]!r}"
    logged = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=TOKYO)
    assert before - timedelta(seconds=2) <= logged <= after + timedelta(seconds=2), \
        f"Timestamp {match.group(1)} is not the current Asia/Tokyo local time"


def exercise_binary(binary):
    assert_one_run(binary, "ALERT", listener=False)
    assert_one_run(binary, "OK", listener=True)


def test_monitor_runtime_behavior_and_source():
    # Exercise the submitted artifact on independently controlled TCP failure
    # and success cases.
    exercise_binary(BINARY)

    # Independently compile and exercise the submitted C source as well.
    rebuilt = "/tmp/monitor-rebuilt"
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt], timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert compile_result.returncode == 0, \
        f"monitor.c does not compile: {compile_result.stderr.decode(errors='replace')}"
    exercise_binary(rebuilt)
TEST_EOF

if PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 python3 -I -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
