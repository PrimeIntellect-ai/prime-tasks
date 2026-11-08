#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import sqlite3
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import redis

PIPELINE = "/home/user/pipeline.py"
ORCHESTRATOR = "/home/user/orchestrator.py"
VERIFY = "/app/verify.py"


def matching_pids(text):
    result = []
    me = os.getpid()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == me:
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\x00", b" ").decode(errors="ignore")
            if text in cmdline:
                result.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def stop_matching(text):
    pids = matching_pids(text)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and any(os.path.exists(f"/proc/{p}") for p in pids):
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


class CaptureHandler(BaseHTTPRequestHandler):
    received = []
    lock = threading.Lock()

    def do_POST(self):
        if self.path != "/ingest":
            self.send_response(404)
            self.end_headers()
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            logs = payload["logs"]
            if not isinstance(logs, list) or not all(isinstance(x, str) for x in logs):
                raise ValueError("logs must be a list of strings")
            with self.lock:
                self.received.extend(logs)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        except Exception:
            self.send_response(400)
            self.end_headers()

    def log_message(self, *args):
        pass


def captured():
    with CaptureHandler.lock:
        return list(CaptureHandler.received)


def clear_capture():
    with CaptureHandler.lock:
        CaptureHandler.received.clear()


def make_records(nonce, start, count):
    raw = []
    expected = []
    for i in range(start, start + count):
        card = f"{1100 + i % 8000:04d}-{2200 + i % 7000:04d}-{3300 + i % 6000:04d}-{4400 + i % 5000:04d}"
        ip = f"10.20.{i % 200}.{(i * 7) % 254 + 1}"
        prefix = f"2026-09-11T12:{i % 60:02d}:00Z INFO req={nonce}-{i} URL=https://shop.example/items/{i}"
        line = f"{prefix} User user{i}@example.com logged in from {ip} using card {card}"
        masked = f"{prefix} User [MASKED]@example.com logged in from 10.20.{i % 200}.XXX using card XXXX-XXXX-XXXX-{card[-4:]}"
        raw.append(line)
        expected.append(masked)
    return raw, expected


def wait_for_accuracy(expected, timeout=10):
    deadline = time.time() + timeout
    required = (95 * len(expected) + 99) // 100
    while time.time() < deadline:
        output = captured()
        correct = sum(1 for item in expected if item in output)
        if correct >= required:
            return correct
        time.sleep(0.1)
    output = captured()
    return sum(1 for item in expected if item in output)


def test_complete_pipeline_and_orchestration():
    # Preserve the original artifact-existence assertions.
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is missing."
    assert os.path.isfile(ORCHESTRATOR), f"{ORCHESTRATOR} is missing."
    assert os.path.isfile(VERIFY), f"Verifier script {VERIFY} is missing."

    for path in (PIPELINE, ORCHESTRATOR):
        compiled = subprocess.run(["python3", "-m", "py_compile", path], capture_output=True, text=True)
        assert compiled.returncode == 0, f"{path} is not valid Python: {compiled.stderr}"

    # The instruction requires that the submitted orchestrator was started in the background.
    assert matching_pids(ORCHESTRATOR), "The submitted orchestrator is not running in the background."

    stop_matching(ORCHESTRATOR)
    stop_matching("/app/log_generator.py")
    stop_matching("/app/flask_api.py")

    try:
        r = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
        r.ping()
    except Exception:
        subprocess.run(["redis-server", "--daemonize", "yes"], check=True)
        time.sleep(0.5)
        r = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
        r.ping()

    server = ThreadingHTTPServer(("127.0.0.1", 5000), CaptureHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    nonce = secrets.token_hex(12)
    try:
        # Execute pipeline.py itself against a private, unpredictable batch. Verify the
        # 100-item cap, FIFO removal, POST payload, masking, and metadata preservation.
        r.delete("raw_logs")
        clear_capture()
        raw, expected = make_records(nonce, 0, 105)
        r.rpush("raw_logs", *raw)
        run = subprocess.run(["python3", PIPELINE], capture_output=True, text=True, timeout=15)
        assert run.returncode == 0, f"pipeline.py failed:\nSTDOUT: {run.stdout}\nSTDERR: {run.stderr}"
        assert r.lrange("raw_logs", 0, -1) == raw[100:], "A single pipeline run must LPOP at most the first 100 logs."
        direct_output = captured()
        correct = sum(1 for item in expected[:100] if item in direct_output)
        assert correct / 100 >= 0.95, f"Masking/preservation accuracy was {correct / 100:.3f}, below 0.95."

        # Start the submitted scheduler and give it two batches on separate cycles.
        # This proves it repeatedly invokes the pipeline rather than running it once.
        r.delete("raw_logs")
        clear_capture()
        orch = subprocess.Popen(
            ["python3", ORCHESTRATOR],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            batch1, masked1 = make_records(nonce, 1000, 20)
            r.rpush("raw_logs", *batch1)
            score1 = wait_for_accuracy(masked1, timeout=10)
            assert score1 / len(masked1) >= 0.95, "The orchestrator did not correctly process its first batch."

            clear_capture()
            batch2, masked2 = make_records(nonce, 2000, 20)
            r.rpush("raw_logs", *batch2)
            score2 = wait_for_accuracy(masked2, timeout=10)
            assert score2 / len(masked2) >= 0.95, "The orchestrator did not continue processing a later batch."
            assert orch.poll() is None, "orchestrator.py exited instead of running continuously."
        finally:
            if orch.poll() is None:
                os.killpg(orch.pid, signal.SIGTERM)
                try:
                    orch.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(orch.pid, signal.SIGKILL)

        # Retain execution of the originally asserted verifier after ensuring its DB
        # contains a record produced by the behavioral test.
        conn = sqlite3.connect("/app/clean_logs.db")
        conn.execute("CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY, log TEXT)")
        conn.execute("INSERT INTO logs (log) VALUES (?)", (masked2[0],))
        conn.commit()
        conn.close()
        old_verify = subprocess.run(["python3", VERIFY], capture_output=True, text=True)
        assert old_verify.returncode == 0, (
            f"Existing verifier failed. Exit code: {old_verify.returncode}\n"
            f"STDOUT: {old_verify.stdout}\nSTDERR: {old_verify.stderr}"
        )
    finally:
        server.shutdown()
        server.server_close()
        r.delete("raw_logs")
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
