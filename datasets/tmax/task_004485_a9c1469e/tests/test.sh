#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

import pytest
import redis


def run_detector(script, path):
    return subprocess.run(
        ["python3", script, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).returncode


def test_detector_adversarial_corpus():
    detector_script = "/home/user/detector.py"
    assert os.path.isfile(detector_script), f"Detector script not found at {detector_script}"

    # Preserve the original corpus checks.
    evil_dir = "/home/user/corpora/evil"
    clean_dir = "/home/user/corpora/clean"
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".jsonl")]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".jsonl")]

    evil_bypassed = [os.path.basename(p) for p in evil_files if run_detector(detector_script, p) != 1]
    clean_modified = [os.path.basename(p) for p in clean_files if run_detector(detector_script, p) != 0]

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not errors, " ; ".join(errors)

    # Exercise content-derived cases at unpredictable, unlabeled paths. Both
    # classes live in the same directory and have random names and values.
    with tempfile.TemporaryDirectory(prefix="telemetry-corpus-") as td:
        cases = []
        for _ in range(6):
            clean_path = os.path.join(td, secrets.token_hex(12) + ".jsonl")
            evil_path = os.path.join(td, secrets.token_hex(12) + ".jsonl")

            clean_rows = [
                {"id": secrets.token_hex(6), "duration": 0.1 + secrets.randbelow(50000) / 1000.0}
                for _ in range(3 + secrets.randbelow(5))
            ]
            evil_rows = [
                {"id": secrets.token_hex(6), "duration": 0.1 + secrets.randbelow(50000) / 1000.0}
                for _ in range(2 + secrets.randbelow(4))
            ]
            evil_rows.insert(
                secrets.randbelow(len(evil_rows) + 1),
                {"id": secrets.token_hex(6), "duration": -(0.1 + secrets.randbelow(50000) / 1000.0)},
            )

            with open(clean_path, "w") as f:
                for row in clean_rows:
                    f.write(json.dumps(row) + "\n")
            with open(evil_path, "w") as f:
                for row in evil_rows:
                    f.write(json.dumps(row) + "\n")

            cases.extend([(clean_path, 0), (evil_path, 1)])

        # Do not expose the expected class through invocation order.
        cases.sort(key=lambda item: secrets.token_bytes(16))
        for path, expected in cases:
            actual = run_detector(detector_script, path)
            assert actual == expected, (
                f"Detector returned {actual} instead of {expected} for generated JSONL content"
            )


def worker_pids():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="ignore")
            if "/home/user/app/worker.py" in cmdline:
                found.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def cleanup_services(process=None):
    for pid in worker_pids():
        try:
            os.kill(pid, signal.SIGCONT)
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    subprocess.run(["pkill", "-f", "/home/user/app/api.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["redis-cli", "-p", "6380", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "redis-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()


def wait_for_services(client, timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            client.ping()
            req = urllib.request.Request("http://127.0.0.1:5000/", method="GET")
            try:
                urllib.request.urlopen(req, timeout=0.5).close()
            except urllib.error.HTTPError:
                # A Flask 404 still proves the HTTP service is listening.
                pass
            return
        except Exception as exc:
            last_error = exc
            time.sleep(0.15)
    pytest.fail(f"Services did not become ready: {last_error}")


def test_end_to_end_telemetry_flow():
    start_script = "/home/user/app/start_services.sh"
    assert os.path.isfile(start_script), f"Start script not found at {start_script}"

    cleanup_services()
    log_file = "/home/user/app/processed_events.log"
    try:
        os.remove(log_file)
    except FileNotFoundError:
        pass

    process = subprocess.Popen(
        ["bash", start_script],
        cwd="/home/user/app",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    client = redis.Redis(host="127.0.0.1", port=6380, db=0, socket_timeout=1)

    try:
        wait_for_services(client)

        pids = worker_pids()
        assert pids, "start_services.sh did not start /home/user/app/worker.py"
        for pid in pids:
            os.kill(pid, signal.SIGSTOP)

        client.flushdb()
        token = secrets.token_hex(20)
        target = datetime.now(timezone.utc).replace(microsecond=0) - timedelta(seconds=5)
        timestamp = target.strftime("%Y-%m-%dT%H:%M:%SZ")
        req_data = json.dumps({
            "id": token,
            "event_id": token,
            "timestamp": timestamp,
        }).encode("utf-8")
        req = urllib.request.Request(
            "http://127.0.0.1:5000/ingest",
            data=req_data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=3) as response:
                assert response.status == 200, f"Expected status 200, got {response.status}"
        except urllib.error.URLError as exc:
            pytest.fail(f"Failed to connect to Flask API: {exc}")

        # The worker is stopped, so the event must be observable in the real
        # configured Redis instance. This proves the API did not merely return
        # 200 or prewrite a log.
        queued = client.lrange("telemetry", 0, -1)
        assert queued, "The API did not enqueue the event in Redis on port 6380"
        decoded = [json.loads(value) for value in queued]
        matching = [row for row in decoded if row.get("id") == token or row.get("event_id") == token]
        assert matching, "Redis did not contain the event submitted to the API"
        queued_event = matching[0]
        assert "parsed_timestamp" in queued_event, "API did not normalize the incoming timestamp"

        parsed = datetime.fromisoformat(queued_event["parsed_timestamp"].replace("Z", "+00:00"))
        assert parsed.tzinfo is not None and parsed.utcoffset() is not None, "Normalized timestamp is timezone-naive"
        assert parsed.utcoffset() == timedelta(0), "Normalized timestamp is not UTC"
        assert abs((parsed.astimezone(timezone.utc) - target).total_seconds()) < 0.001

        for pid in pids:
            os.kill(pid, signal.SIGCONT)

        deadline = time.time() + 8
        matched_log = None
        raw_logs = ""
        while time.time() < deadline:
            if os.path.isfile(log_file):
                with open(log_file) as f:
                    raw_logs = f.read()
                for line in raw_logs.splitlines():
                    try:
                        row = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if row.get("id") == token or row.get("event_id") == token:
                        matched_log = row
                        break
            if matched_log is not None:
                break
            time.sleep(0.1)

        assert os.path.isfile(log_file), f"Log file {log_file} was not created."
        assert token in raw_logs, "The submitted event was not found in the processed logs."
        assert "-5" not in raw_logs, "Negative duration found in logs."
        assert matched_log is not None, "Worker did not write a JSON log for the submitted Redis event"
        assert isinstance(matched_log.get("duration"), (int, float)), "Worker did not log a numeric duration"
        duration = float(matched_log["duration"])
        assert 4.5 <= duration <= 8.0, f"Expected a five-second duration (allowing processing delay), got {duration}"
    finally:
        cleanup_services(process)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
