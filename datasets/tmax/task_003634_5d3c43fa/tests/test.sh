#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure verification exercises a fresh launch through the submitted startup script.
pkill -f 'uvicorn services.api_gateway:app' 2>/dev/null || true
pkill -f 'services/payment_mock.py' 2>/dev/null || true
pkill -f 'services.payment_mock.py' 2>/dev/null || true
pkill -f 'services/ticket_worker.py' 2>/dev/null || true
pkill -f 'services.ticket_worker.py' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import http.client
import json
import os
import re
import sqlite3
import subprocess
import time


def parse_last_json(text):
    lines = [line for line in text.splitlines() if line.strip()]
    assert lines, "Expected JSON output, but output was empty"
    try:
        return json.loads(lines[-1])
    except json.JSONDecodeError:
        assert False, f"Could not parse JSON from output. Last line was: {lines[-1]}"


def test_final_state():
    worker_path = "/app/services/ticket_worker.py"
    start_script = "/app/start_services.sh"
    load_test_path = "/app/tests/load_test.py"
    results_path = "/home/user/load_test_results.txt"
    db_path = "/app/data/bookings.db"
    dump_path = "/app/dumps/worker_crash.core"

    for path in (worker_path, start_script, load_test_path, results_path, db_path, dump_path):
        assert os.path.isfile(path), f"Required file not found: {path}"

    # Derive the expected secret from the supplied crash dump rather than trusting
    # a submitted configuration value.
    dump = open(dump_path, "rb").read()
    matches = re.findall(rb"PAYMENT_SEC_[A-Za-z0-9]+", dump)
    assert matches, "No payment API key could be recovered from the crash dump"
    expected_key = matches[0].decode("ascii")

    # Validate that the recovered database is a usable SQLite database, its WAL
    # can be checkpointed, and the required table remains readable and writable.
    con = sqlite3.connect(db_path, timeout=5)
    try:
        quick_check = con.execute("PRAGMA quick_check").fetchone()[0]
        assert quick_check == "ok", f"Database integrity check failed: {quick_check}"
        table = con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='bookings'"
        ).fetchone()
        assert table is not None, "Recovered database is missing the bookings table"
        con.execute("SELECT id, status FROM bookings").fetchall()
        con.execute("BEGIN")
        con.execute("INSERT INTO bookings(status) VALUES (?)", ("verifier_probe",))
        con.rollback()
        checkpoint = con.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        assert checkpoint[0] == 0, f"WAL checkpoint was busy or failed: {checkpoint}"
    finally:
        con.close()

    # Exercise the repaired worker in a separate interpreter so a real deadlock
    # cannot hang the verifier.
    worker_probe = r'''
import importlib.util
import sys
import threading
spec = importlib.util.spec_from_file_location("submitted_worker", "/app/services/ticket_worker.py")
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
assert callable(getattr(w, "process_a", None))
assert callable(getattr(w, "process_b", None))
t1 = threading.Thread(target=w.process_a, daemon=True)
t2 = threading.Thread(target=w.process_b, daemon=True)
t1.start(); t2.start()
t1.join(3); t2.join(3)
if t1.is_alive() or t2.is_alive():
    sys.exit(20)

pool = w.ConnectionPool()
limit = int(pool.max_limit)
assert limit > 0
for _ in range(limit):
    pool.get_connection()
assert pool.active == limit, (pool.active, limit)
try:
    pool.get_connection()
except Exception:
    pass
else:
    raise AssertionError("Pool accepted a connection beyond max_limit")
assert pool.active == limit, "Rejected acquisition leaked pool capacity"
'''
    try:
        probe = subprocess.run(
            ["python3", "-c", worker_probe], capture_output=True, text=True, timeout=10
        )
    except subprocess.TimeoutExpired:
        assert False, "Worker probe timed out, indicating a deadlock or blocking pool boundary"
    assert probe.returncode == 0, (
        f"Worker deadlock/pool probe failed (exit {probe.returncode}).\n"
        f"Stdout: {probe.stdout}\nStderr: {probe.stderr}"
    )

    # The requested saved load-test result must exist and retain the original
    # successful-count and throughput assertions.
    saved = parse_last_json(open(results_path, encoding="utf-8").read())
    assert "throughput" in saved, f"Missing 'throughput' in saved load-test output: {saved}"
    assert "successful" in saved, f"Missing 'successful' in saved load-test output: {saved}"
    assert int(saved["successful"]) == 5000, (
        f"Expected 5000 successful bookings, but got {saved['successful']}"
    )
    assert float(saved["throughput"]) >= 800.0, (
        f"Saved throughput of {float(saved['throughput']):.2f} req/sec is below 800.0"
    )

    os.chmod(start_script, 0o755)
    launcher = subprocess.Popen(
        [start_script], cwd="/app", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        # Wait for the API started by start_services.sh, rather than accepting a
        # self-reported load-test result from an unstarted system.
        deadline = time.time() + 12
        while time.time() < deadline:
            try:
                c = http.client.HTTPConnection("127.0.0.1", 8000, timeout=1)
                c.request("POST", "/book", body=b"", headers={"Content-Length": "0"})
                r = c.getresponse()
                body = r.read()
                c.close()
                if r.status == 200 and json.loads(body.decode()).get("status") == "queued":
                    break
            except Exception:
                time.sleep(0.2)
        else:
            assert False, "API gateway did not start correctly via /app/start_services.sh"

        # Confirm that the freshly launched payment service actually received the
        # key recovered from the dump in its process environment.
        payment_found = False
        payment_has_key = False
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            try:
                cmd = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ")
                if b"payment_mock.py" not in cmd:
                    continue
                payment_found = True
                env_items = open(f"/proc/{entry}/environ", "rb").read().split(b"\0")
                payment_has_key = (f"PAYMENT_API_KEY={expected_key}".encode() in env_items)
                if payment_has_key:
                    break
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                continue
        assert payment_found, "payment_mock.py was not launched by start_services.sh"
        assert payment_has_key, "The launched payment service does not have the recovered PAYMENT_API_KEY"

        # Independently generate and count 5000 real HTTP bookings. The expected
        # values and elapsed time are measured by the verifier, not read from the
        # shipped load-test script.
        workers = 50
        per_worker = 100

        def issue_batch(_):
            successful = 0
            conn = None
            for _ in range(per_worker):
                try:
                    if conn is None:
                        conn = http.client.HTTPConnection("127.0.0.1", 8000, timeout=5)
                    conn.request("POST", "/book", body=b"", headers={"Content-Length": "0"})
                    response = conn.getresponse()
                    payload = response.read()
                    if response.status == 200 and json.loads(payload.decode()).get("status") == "queued":
                        successful += 1
                except Exception:
                    if conn is not None:
                        try:
                            conn.close()
                        except Exception:
                            pass
                    conn = None
            if conn is not None:
                conn.close()
            return successful

        began = time.perf_counter()
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
            counts = list(executor.map(issue_batch, range(workers)))
        elapsed = time.perf_counter() - began
        successful = sum(counts)
        throughput = successful / elapsed if elapsed else float("inf")
        assert successful == 5000, (
            f"Expected 5000 successful real bookings, but got {successful}"
        )
        assert throughput >= 800.0, (
            f"Measured throughput of {throughput:.2f} req/sec is below 800.0 req/sec"
        )

        # Still execute the artifact explicitly demanded by the instruction and
        # retain all assertions made by the original verifier.
        try:
            result = subprocess.run(
                ["python3", load_test_path], capture_output=True, text=True, timeout=45
            )
        except subprocess.TimeoutExpired:
            assert False, "Load test timed out, indicating a deadlock in the worker or API"
        assert result.returncode == 0, (
            f"Load test failed to execute properly.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        )
        data = parse_last_json(result.stdout)
        assert "throughput" in data, f"Missing 'throughput' in load test output: {data}"
        assert "successful" in data, f"Missing 'successful' in load test output: {data}"
        assert int(data["successful"]) == 5000, (
            f"Expected 5000 successful bookings, but got {data['successful']}"
        )
        assert float(data["throughput"]) >= 800.0, (
            f"Throughput of {float(data['throughput']):.2f} req/sec is below 800.0 req/sec"
        )
    finally:
        launcher.terminate()
        try:
            launcher.wait(timeout=3)
        except subprocess.TimeoutExpired:
            launcher.kill()

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
