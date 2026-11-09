#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import socket
import subprocess
import time
import signal
import pytest

SERVICES = "/home/user/services"
PRODUCER = SERVICES + "/producer.py"
CONSUMER = SERVICES + "/consumer.py"
MONITOR = SERVICES + "/monitor.py"
SOCKET_PATH = SERVICES + "/sockets/app.sock"
LOG_PATH = SERVICES + "/logs/processing.log"
ALERTS_PATH = SERVICES + "/alerts.json"
DATA_STORE = SERVICES + "/data_store/"


def matching_pids(script_path):
    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\\0") if x]
            if script_path in args:
                result.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def stop_script(script_path):
    pids = matching_pids(script_path)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(os.path.exists(f"/proc/{pid}") for pid in pids):
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def start_script(script_path):
    return subprocess.Popen(
        ["python3", script_path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def start_services():
    if os.path.exists(SOCKET_PATH):
        try:
            os.unlink(SOCKET_PATH)
        except FileNotFoundError:
            pass
    start_script(CONSUMER)
    deadline = time.time() + 4
    while time.time() < deadline and not os.path.exists(SOCKET_PATH):
        time.sleep(0.05)
    assert os.path.exists(SOCKET_PATH), "consumer.py did not create its Unix socket."
    start_script(PRODUCER)


def directory_size():
    expected_size = 0
    if os.path.exists(DATA_STORE):
        for f in os.listdir(DATA_STORE):
            file_path = os.path.join(DATA_STORE, f)
            if os.path.isfile(file_path):
                expected_size += os.path.getsize(file_path)
    return expected_size


def append_log(line):
    with open(LOG_PATH, "a") as f:
        f.write(line + "\n")
        f.flush()
        os.fsync(f.fileno())


def test_producer_patched():
    producer_path = PRODUCER
    assert os.path.isfile(producer_path), f"File {producer_path} does not exist."

    with open(producer_path, "r") as f:
        content = f.read()

    assert "/home/user/services/sockets/app.sock" in content, (
        "producer.py has not been patched to use the correct socket path "
        "(/home/user/services/sockets/app.sock)."
    )
    assert "/tmp/app.sock" not in content, (
        "producer.py still contains the old incorrect socket path (/tmp/app.sock)."
    )


def test_producer_executes_and_uses_correct_socket():
    stop_script(PRODUCER)
    stop_script(CONSUMER)
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    producer_proc = None
    try:
        server.bind(SOCKET_PATH)
        server.listen(1)
        server.settimeout(7)
        producer_proc = start_script(PRODUCER)
        conn, _ = server.accept()
        with conn:
            conn.settimeout(2)
            received = conn.recv(4096).decode("utf-8")
        assert received in {
            "INFO: Transaction processed",
            "INFO: Cache updated",
            "ERROR: Sync failed - target filesystem unresponsive",
        }, f"producer.py sent an unexpected payload: {received!r}"
    finally:
        if producer_proc is not None and producer_proc.poll() is None:
            producer_proc.terminate()
            try:
                producer_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                producer_proc.kill()
        server.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        start_services()

    before = os.path.getsize(LOG_PATH)
    deadline = time.time() + 7
    while time.time() < deadline and os.path.getsize(LOG_PATH) <= before:
        time.sleep(0.1)
    assert os.path.getsize(LOG_PATH) > before, (
        "The restarted producer.py and consumer.py did not communicate and append to processing.log."
    )


def test_monitor_reacts_only_to_new_error_lines():
    assert os.path.isfile(MONITOR), f"File {MONITOR} does not exist."

    stop_script(PRODUCER)
    stop_script(MONITOR)

    probe_path = os.path.join(DATA_STORE, "verifier_probe.bin")
    with open(probe_path, "wb") as f:
        f.write(b"V" * 123457)
        f.flush()
        os.fsync(f.fileno())
    expected_size = directory_size()

    open(LOG_PATH, "w").close()
    open(ALERTS_PATH, "w").close()
    monitor_proc = start_script(MONITOR)

    try:
        time.sleep(1)
        assert monitor_proc.poll() is None, "monitor.py exited instead of continuously monitoring."

        append_log("INFO: verifier non-error control line")
        time.sleep(1.5)
        assert os.path.getsize(ALERTS_PATH) == 0, (
            "monitor.py emitted an alert for a line that was not the exact sync error."
        )

        append_log("ERROR: Sync failed - target filesystem unresponsive")
        deadline = time.time() + 8
        while time.time() < deadline and os.path.getsize(ALERTS_PATH) == 0:
            assert monitor_proc.poll() is None, "monitor.py exited while waiting for a new log line."
            time.sleep(0.1)

        assert os.path.getsize(ALERTS_PATH) > 0, (
            "monitor.py did not append an alert after the verifier appended a controlled error line."
        )

        with open(ALERTS_PATH, "r") as f:
            raw_lines = f.read().splitlines()
        assert raw_lines, "No alert JSON line was written for the controlled error."
        for line in raw_lines:
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON in alerts.json: {line}")
            assert set(data) == {"event", "data_store_size_bytes"}, (
                f"Alert does not strictly match the required schema: {data}"
            )
            assert data["event"] == "SYNC_ERROR"
            assert isinstance(data["data_store_size_bytes"], int)
            assert data["data_store_size_bytes"] == expected_size, (
                f"Expected data_store_size_bytes to be {expected_size}, "
                f"got {data['data_store_size_bytes']}"
            )
    finally:
        if not matching_pids(MONITOR):
            start_script(MONITOR)
        if not matching_pids(PRODUCER):
            start_script(PRODUCER)


def test_processes_running():
    # Give the processes a moment to be fully up if they were just started
    time.sleep(1)

    try:
        output = subprocess.check_output(["ps", "aux"], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute `ps aux` to check running processes.")

    assert "consumer.py" in output, "consumer.py is not running in the background."
    assert "producer.py" in output, "producer.py is not running in the background."
    assert "monitor.py" in output, "monitor.py is not running in the background."


def test_alerts_json_schema_and_content():
    alerts_path = ALERTS_PATH

    # Wait briefly to ensure at least one error might have been processed
    # The producer sleeps 1 sec and randomly picks from 3 messages, so an error should appear soon.
    # We will wait up to 10 seconds for the file to be created and populated.
    for _ in range(20):
        if os.path.exists(alerts_path) and os.path.getsize(alerts_path) > 0:
            break
        time.sleep(0.5)

    assert os.path.isfile(alerts_path), f"Alerts file {alerts_path} does not exist."
    assert os.path.getsize(alerts_path) > 0, f"Alerts file {alerts_path} is empty."

    # Calculate expected directory size
    expected_size = directory_size()

    with open(alerts_path, "r") as f:
        lines = f.read().strip().split('\n')

    assert len(lines) > 0, "No JSON lines found in alerts.json."

    for line in lines:
        if not line.strip():
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in alerts.json: {line}")

        assert "event" in data, f"Missing 'event' key in JSON: {data}"
        assert data["event"] == "SYNC_ERROR", f"Incorrect 'event' value: {data['event']}"

        assert "data_store_size_bytes" in data, f"Missing 'data_store_size_bytes' key in JSON: {data}"
        assert isinstance(data["data_store_size_bytes"], int), "data_store_size_bytes must be an integer."
        assert data["data_store_size_bytes"] == expected_size, (
            f"Expected data_store_size_bytes to be {expected_size}, got {data['data_store_size_bytes']}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
