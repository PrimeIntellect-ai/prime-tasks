#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import socket
import subprocess
import tempfile
import threading
import time

import pytest

BINARY = "/home/user/disk_monitor"
SOURCE = "/home/user/main.rs"
DATA_DIR = "/home/user/data"
WRAPPER = "/home/user/run_monitor.sh"
LOG_PATH = "/home/user/monitor_status.log"
ALERT_DIR = "/home/user/alerts"
EMAIL_PATH = "/home/user/alerts/email.txt"
THRESHOLD = 50_000_000


def test_compiled_binary_exists():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "disk_monitor must be a compiled executable, not a script."


def test_mail_offline_behavior():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    # Confirm the port is available immediately before exercising the offline path.
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    probe.bind(("127.0.0.1", 2525))
    probe.close()

    result = subprocess.run(
        ["bash", WRAPPER],
        capture_output=True,
        env={"PATH": "/usr/bin:/bin"},
        timeout=15,
    )

    assert result.returncode == 1, "Script should exit with status 1 when mail is offline."
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "Mail offline", f"Log file content incorrect. Expected 'Mail offline', got '{content}'."


def clear_data():
    os.makedirs(DATA_DIR, exist_ok=True)
    for name in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)


def make_files(sizes):
    clear_data()
    for index, size in enumerate(sizes):
        name = f"sample_{secrets.token_hex(6)}_{index}.dat"
        with open(os.path.join(DATA_DIR, name), "wb") as f:
            f.truncate(size)


def exercise_monitor(binary):
    with tempfile.TemporaryDirectory() as temp:
        helper_dir = os.path.join(temp, "bin")
        alert_dir = os.path.join(temp, "alerts")
        os.makedirs(helper_dir)
        os.makedirs(alert_dir)
        marker = os.path.join(alert_dir, "invoked")
        helper = os.path.join(helper_dir, "send_alert.sh")
        with open(helper, "w") as f:
            f.write("#!/bin/sh\n")
            f.write("printf '%s\\n' \"$ALERT_DIR\" > \"$ALERT_DIR/invoked\"\n")
        os.chmod(helper, 0o755)

        env = {"PATH": helper_dir, "ALERT_DIR": alert_dir}

        split = 20_000_000 + secrets.randbelow(5_000_000)
        cases = [
            ([split, THRESHOLD - split], False),       # Exactly 50 MB must not alert.
            ([17_000_000, 18_000_000, 14_000_000], False),
            ([24_000_000 + secrets.randbelow(500_000),
              26_000_001 + secrets.randbelow(500_000)], True),
        ]

        for sizes, should_alert in cases:
            make_files(sizes)
            if os.path.exists(marker):
                os.remove(marker)
            result = subprocess.run([binary], capture_output=True, env=env, timeout=20)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            assert os.path.exists(marker) == should_alert, (
                f"Monitor alert behavior was wrong for total size {sum(sizes)} bytes."
            )
            if should_alert:
                with open(marker, "r") as f:
                    assert f.read().strip() == alert_dir, "ALERT_DIR was not passed to send_alert.sh."


def test_rust_source_and_binary_calculate_sizes_and_use_path():
    assert os.path.isfile(SOURCE), f"Rust source {SOURCE} does not exist."

    # Test the submitted artifact itself on derived data sets and a PATH-only spy helper.
    exercise_monitor(BINARY)

    # Also compile the submitted source independently so an unrelated executable cannot pass.
    with tempfile.TemporaryDirectory() as temp:
        rebuilt = os.path.join(temp, "disk_monitor_from_source")
        result = subprocess.run(
            ["rustc", SOURCE, "-o", rebuilt],
            capture_output=True,
            timeout=60,
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        exercise_monitor(rebuilt)


def dummy_server(ready, errors):
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind(("127.0.0.1", 2525))
        server_socket.listen(1)
        server_socket.settimeout(10.0)
        ready.set()
        conn, _ = server_socket.accept()
        conn.close()
    except Exception as exc:
        errors.append(exc)
        ready.set()
    finally:
        server_socket.close()


def run_online_wrapper():
    ready = threading.Event()
    errors = []
    thread = threading.Thread(target=dummy_server, args=(ready, errors), daemon=True)
    thread.start()
    assert ready.wait(3), "Mail relay test listener did not start."
    assert not errors, f"Mail relay test listener failed: {errors}"
    result = subprocess.run(
        ["bash", WRAPPER],
        capture_output=True,
        env={"PATH": "/usr/bin:/bin"},
        timeout=20,
    )
    thread.join(timeout=3)
    assert not errors, f"Mail relay test listener failed: {errors}"
    return result


def test_normal_run_behavior():
    # Use an above-threshold data set for the required final integration behavior.
    make_files([25_000_000, 25_000_001 + secrets.randbelow(500_000)])

    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    if os.path.isdir(ALERT_DIR):
        shutil.rmtree(ALERT_DIR)

    # Interpose a probe which then executes the real compiled monitor. This verifies
    # that the wrapper actually invokes /home/user/disk_monitor.
    saved_binary = BINARY + ".verifier_real"
    invocation_marker = "/tmp/disk_monitor_wrapper_invoked"
    if os.path.exists(invocation_marker):
        os.remove(invocation_marker)
    if os.path.exists(saved_binary):
        os.remove(saved_binary)
    os.replace(BINARY, saved_binary)
    try:
        with open(BINARY, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"echo invoked > {invocation_marker}\n")
            f.write(f"exec {saved_binary} \"$@\"\n")
        os.chmod(BINARY, 0o755)

        result = run_online_wrapper()
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isfile(invocation_marker), "Wrapper did not execute /home/user/disk_monitor."

        assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created on successful run."
        with open(LOG_PATH, "r") as f:
            log_content = f.read().strip()
        assert log_content == "Success", f"Log file content incorrect. Expected 'Success', got '{log_content}'."

        assert os.path.isdir(ALERT_DIR), "Directory /home/user/alerts was not created."
        assert os.path.isfile(EMAIL_PATH), f"Email alert file {EMAIL_PATH} was not created."
        with open(EMAIL_PATH, "r") as f:
            email_content = f.read().strip()
        assert email_content == "QUOTA EXCEEDED", f"Email file content incorrect. Expected 'QUOTA EXCEEDED', got '{email_content}'."

        # A second successful run verifies directory creation is idempotent.
        os.remove(invocation_marker)
        second = run_online_wrapper()
        assert second.returncode == 0, second.stderr.decode(errors="replace")
        assert os.path.isfile(invocation_marker), "Wrapper did not invoke the monitor on its second run."
        with open(LOG_PATH, "r") as f:
            assert f.read().strip() == "Success"
        with open(EMAIL_PATH, "r") as f:
            assert f.read().strip() == "QUOTA EXCEEDED"
    finally:
        if os.path.exists(BINARY):
            os.remove(BINARY)
        if os.path.exists(saved_binary):
            os.replace(saved_binary, BINARY)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
