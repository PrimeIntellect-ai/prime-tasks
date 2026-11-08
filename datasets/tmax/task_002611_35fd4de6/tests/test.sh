#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import runpy
import socket
import subprocess
import threading
from unittest import mock

import pytest

SCRIPT_PATH = "/home/user/check_deploy.py"
JSON_PATH = "/home/user/deploy_status.json"
BASHRC_PATH = "/home/user/.bashrc"
TZ_LINE = "export TZ=Asia/Tokyo"
CRON_LINE = "*/5 * * * * /usr/bin/python3 /home/user/check_deploy.py"


def read_status():
    assert os.path.isfile(JSON_PATH), f"JSON output file {JSON_PATH} does not exist."
    with open(JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")


def run_script():
    try:
        subprocess.check_call(["/usr/bin/python3", SCRIPT_PATH])
    except subprocess.CalledProcessError:
        pytest.fail(f"Execution of {SCRIPT_PATH} failed.")


def assert_single_configuration_entries():
    with open(BASHRC_PATH, "r") as f:
        content = f.read()
    count = content.splitlines().count(TZ_LINE)
    assert count == 1, f"Idempotency failed: found {count} occurrences of '{TZ_LINE}' in {BASHRC_PATH}."

    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read crontab: {e.output}")
    count = output.splitlines().count(CRON_LINE)
    assert count == 1, f"Idempotency failed: found {count} occurrences of '{CRON_LINE}' in crontab."


class TCPListener:
    def __init__(self, port):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", port))
        self.sock.listen(8)
        self.sock.settimeout(0.1)
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        while not self.stopped.is_set():
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            conn.close()

    def close(self):
        if not self.stopped.is_set():
            self.stopped.set()
            self.sock.close()
            self.thread.join(timeout=1)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_json_output():
    data = read_status()
    assert data.get("stage1") == "offline", "stage1 should be 'offline'"
    assert data.get("stage2") == "offline", "stage2 should be 'offline'"
    assert data.get("last_checked_tz") == "Asia/Tokyo", "last_checked_tz should be 'Asia/Tokyo'"


def test_bashrc_updated():
    assert os.path.isfile(BASHRC_PATH), f"{BASHRC_PATH} does not exist."
    with open(BASHRC_PATH, "r") as f:
        content = f.read()
    count = content.splitlines().count(TZ_LINE)
    assert count >= 1, f"Could not find '{TZ_LINE}' in {BASHRC_PATH}."


def test_crontab_updated():
    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read crontab: {e.output}")
    count = output.splitlines().count(CRON_LINE)
    assert count >= 1, f"Could not find '{CRON_LINE}' in crontab."


def test_idempotency():
    run_script()
    assert_single_configuration_entries()


def test_live_connectivity_controls_status():
    stage1 = TCPListener(8081)
    stage2 = TCPListener(8082)
    try:
        run_script()
        data = read_status()
        assert data.get("stage1") == "ready", "stage1 should be ready while port 8081 accepts TCP connections"
        assert data.get("stage2") == "ready", "stage2 should be ready while port 8082 accepts TCP connections"
        assert data.get("last_checked_tz") == "Asia/Tokyo"

        stage2.close()
        run_script()
        data = read_status()
        assert data.get("stage1") == "ready", "stage1 should remain ready while port 8081 accepts connections"
        assert data.get("stage2") == "offline", "stage2 should become offline after its listener stops"
        assert data.get("last_checked_tz") == "Asia/Tokyo"
    finally:
        stage1.close()
        stage2.close()

    run_script()
    data = read_status()
    assert data.get("stage1") == "offline"
    assert data.get("stage2") == "offline"
    assert data.get("last_checked_tz") == "Asia/Tokyo"
    assert_single_configuration_entries()


def test_each_tcp_attempt_uses_one_second_timeout():
    events = []
    default_timeout = [None]

    class FakeSocket:
        def __init__(self, *args, **kwargs):
            self.timeout = default_timeout[0]

        def settimeout(self, value):
            self.timeout = value

        def connect(self, address):
            host, port = address[0], address[1]
            events.append((host, port, self.timeout))
            if port == 8082:
                raise ConnectionRefusedError("simulated offline port")

        def connect_ex(self, address):
            host, port = address[0], address[1]
            events.append((host, port, self.timeout))
            return 0 if port == 8081 else 111

        def close(self):
            pass

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            self.close()

    def fake_create_connection(address, timeout=socket._GLOBAL_DEFAULT_TIMEOUT, source_address=None, all_errors=False):
        effective_timeout = default_timeout[0] if timeout is socket._GLOBAL_DEFAULT_TIMEOUT else timeout
        host, port = address[0], address[1]
        events.append((host, port, effective_timeout))
        if port == 8082:
            raise ConnectionRefusedError("simulated offline port")
        return FakeSocket()

    def fake_setdefaulttimeout(value):
        default_timeout[0] = value

    with mock.patch.object(socket, "socket", FakeSocket), \
         mock.patch.object(socket, "create_connection", fake_create_connection), \
         mock.patch.object(socket, "setdefaulttimeout", fake_setdefaulttimeout):
        try:
            runpy.run_path(SCRIPT_PATH, run_name="__main__")
        except SystemExit as e:
            assert e.code in (None, 0), f"Script exited unsuccessfully with code {e.code}"

    for port in (8081, 8082):
        matching = [(host, timeout) for host, seen_port, timeout in events if seen_port == port]
        assert matching, f"No TCP connection attempt was made to port {port}"
        assert any(host == "127.0.0.1" and timeout == 1 for host, timeout in matching), \
            f"Port {port} was not checked at 127.0.0.1 with a one-second timeout; observed {matching}"

    data = read_status()
    assert data.get("stage1") == "ready", "A successful simulated connection must produce stage1=ready"
    assert data.get("stage2") == "offline", "A failed simulated connection must produce stage2=offline"
    assert data.get("last_checked_tz") == "Asia/Tokyo"
    assert_single_configuration_entries()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
