#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import time
import socket
import threading
import subprocess
import uuid
import importlib.util
from collections import Counter
import pytest

REPORT_PATH = "/home/user/resolution_report.json"
SYSTEM_DIR = "/home/user/ticket_system"
ROUTER_SCRIPT = os.path.join(SYSTEM_DIR, "ticket_router.py")
AUTH_CHECKER = os.path.join(SYSTEM_DIR, "auth_checker")
LOG_FILE = os.path.join(SYSTEM_DIR, "processed_tickets.log")


def auth_result(token):
    return subprocess.run(
        [AUTH_CHECKER, token],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=2,
    ).returncode == 0


def read_log_lines():
    if not os.path.isfile(LOG_FILE):
        return []
    with open(LOG_FILE, "r") as f:
        return f.read().splitlines()


def test_resolution_report_exists_and_valid():
    """Validates the existence, structure, and correctness of the JSON report."""
    assert os.path.isfile(REPORT_PATH), f"The resolution report is missing at {REPORT_PATH}."

    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file at {REPORT_PATH} does not contain valid JSON.")

    assert "missing_ticket_id" in data, "The report is missing the 'missing_ticket_id' key."
    assert "master_token" in data, "The report is missing the 'master_token' key."

    expected_missing_ticket = "TKT-1003"
    expected_master_token = "OVR-9982-ADMIN-SYS"

    assert data["missing_ticket_id"] == expected_missing_ticket, \
        f"Incorrect missing_ticket_id. Expected {expected_missing_ticket}, got {data['missing_ticket_id']}."
    assert data["master_token"] == expected_master_token, \
        f"Incorrect master_token recovered. Expected {expected_master_token}, got {data['master_token']}."


def test_ticket_router_concurrency_fix():
    """Runs the TCP server and verifies concurrent logging and authentication behavior."""
    assert os.path.isfile(ROUTER_SCRIPT), f"The script {ROUTER_SCRIPT} is missing."
    assert os.path.isfile(AUTH_CHECKER) and os.access(AUTH_CHECKER, os.X_OK)

    valid_token = "1234567890"
    invalid_token = "invalid"
    assert auth_result(valid_token), "Test precondition failed: expected valid token was rejected."
    assert not auth_result(invalid_token), "Test precondition failed: expected invalid token was accepted."

    before = Counter(read_log_lines())
    test_ids = [f"TEST-CONC-{uuid.uuid4().hex}" for _ in range(50)]
    invalid_ids = [f"TEST-DENY-{uuid.uuid4().hex}" for _ in range(8)]
    errors = []

    server_proc = subprocess.Popen(
        ["python3", "ticket_router.py"],
        cwd=SYSTEM_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        port_open = False
        for _ in range(20):
            if server_proc.poll() is not None:
                break
            try:
                with socket.create_connection(("127.0.0.1", 8888), timeout=0.1):
                    port_open = True
                    break
            except OSError:
                time.sleep(0.1)

        assert server_proc.poll() is None, "ticket_router.py exited instead of serving on port 8888."
        assert port_open, "The ticket_router.py server did not start or bind to 127.0.0.1:8888 within 2 seconds."

        def send_ticket(t_id, token, expected):
            try:
                with socket.create_connection(("127.0.0.1", 8888), timeout=3) as s:
                    s.settimeout(3)
                    payload = json.dumps({"id": t_id, "token": token})
                    s.sendall(payload.encode("utf-8"))
                    resp = s.recv(1024)
                    if resp != expected:
                        errors.append(f"Unexpected response for {t_id}: {resp!r}, expected {expected!r}")
            except Exception as e:
                errors.append(f"Connection/Transmission error for {t_id}: {e}")

        threads = []
        for t_id in test_ids:
            threads.append(threading.Thread(target=send_ticket, args=(t_id, valid_token, b"OK")))
        for t_id in invalid_ids:
            threads.append(threading.Thread(target=send_ticket, args=(t_id, invalid_token, b"AUTH_FAIL")))

        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=6)

        assert not any(thread.is_alive() for thread in threads), "Some concurrent requests did not complete."
        assert not errors, f"Errors occurred during concurrent request transmission: {errors[:3]}"
    finally:
        server_proc.terminate()
        try:
            server_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            server_proc.kill()
            server_proc.wait(timeout=2)

    assert os.path.isfile(LOG_FILE), f"The log file {LOG_FILE} is missing."
    with open(LOG_FILE, "r") as f:
        log_content = f.read()

    missing_ids = [t_id for t_id in test_ids if t_id not in log_content]
    assert not missing_ids, (
        f"Race condition is not fixed! {len(missing_ids)} out of 50 concurrent tickets were dropped "
        f"from {LOG_FILE}. Missing examples: {missing_ids[:3]}"
    )

    after = Counter(read_log_lines())
    assert all(after[t_id] - before[t_id] == 1 for t_id in test_ids), \
        "Each authenticated concurrent ticket must be logged exactly once."
    assert all(after[t_id] - before[t_id] == 0 for t_id in invalid_ids), \
        "Unauthenticated tickets must not be written to the processed log."


def test_processed_count_is_atomic_and_tracks_only_authenticated_tickets():
    """Exercises handle_client concurrently in-process so processed_count can be verified."""
    old_cwd = os.getcwd()
    os.chdir(SYSTEM_DIR)
    try:
        module_name = f"ticket_router_under_test_{uuid.uuid4().hex}"
        spec = importlib.util.spec_from_file_location(module_name, ROUTER_SCRIPT)
        assert spec is not None and spec.loader is not None
        router = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(router)

        assert hasattr(router, "handle_client"), "ticket_router.py must provide its client handler."
        assert hasattr(router, "processed_count"), "ticket_router.py no longer tracks processed_count."
        router.processed_count = 0

        valid_token = "abcdefghij"
        invalid_token = f"bad-{uuid.uuid4().hex}"
        assert auth_result(valid_token)
        assert not auth_result(invalid_token)

        valid_ids = [f"COUNT-OK-{uuid.uuid4().hex}" for _ in range(50)]
        invalid_ids = [f"COUNT-DENY-{uuid.uuid4().hex}" for _ in range(7)]
        requests = [(t_id, valid_token, b"OK") for t_id in valid_ids]
        requests += [(t_id, invalid_token, b"AUTH_FAIL") for t_id in invalid_ids]
        before = Counter(read_log_lines())

        barrier = threading.Barrier(len(requests))
        clients = []
        workers = []

        def invoke(server_socket):
            barrier.wait(timeout=5)
            router.handle_client(server_socket)

        for t_id, token, expected in requests:
            client, server = socket.socketpair()
            client.settimeout(6)
            client.sendall(json.dumps({"id": t_id, "token": token}).encode("utf-8"))
            clients.append((client, expected, t_id))
            workers.append(threading.Thread(target=invoke, args=(server,)))

        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join(timeout=7)

        assert not any(worker.is_alive() for worker in workers), "Concurrent handlers did not finish."

        response_errors = []
        for client, expected, t_id in clients:
            try:
                response = client.recv(1024)
                if response != expected:
                    response_errors.append(f"{t_id}: got {response!r}, expected {expected!r}")
            except Exception as exc:
                response_errors.append(f"{t_id}: {exc}")
            finally:
                client.close()

        assert not response_errors, f"Handler authentication responses were incorrect: {response_errors[:3]}"
        assert router.processed_count == 50, (
            f"processed_count lost updates or counted rejected tickets: expected 50, got {router.processed_count!r}"
        )

        after = Counter(read_log_lines())
        assert all(after[t_id] - before[t_id] == 1 for t_id in valid_ids), \
            "Authenticated tickets were dropped or duplicated by concurrent handlers."
        assert all(after[t_id] - before[t_id] == 0 for t_id in invalid_ids), \
            "Rejected tickets were logged by the handler."
    finally:
        os.chdir(old_cwd)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
