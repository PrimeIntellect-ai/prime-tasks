#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import pytest
import redis

CLEAN_CORPUS_DIR = "/home/user/tests/corpora/clean/"
EVIL_CORPUS_DIR = "/home/user/tests/corpora/evil/"
CLEAN_JSONL_PATH = "/home/user/etl_output/clean.jsonl"
REJECTED_JSONL_PATH = "/home/user/etl_output/rejected.jsonl"
WORKER_SOURCE = "/home/user/etl_worker.cpp"
WORKER_BINARY = "/home/user/etl_worker"
START_SCRIPT = "/home/user/start_all.sh"


def load_jsonl(path):
    if not os.path.exists(path):
        return {}
    res = {}
    with open(path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            try:
                data = json.loads(line)
                if 'transaction_id' in data:
                    res[data['transaction_id']] = data
            except json.JSONDecodeError:
                pass
    return res


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except (OSError, ProcessLookupError):
        return []


def process_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def all_pids():
    for name in os.listdir("/proc"):
        if name.isdigit():
            yield int(name)


def worker_pids():
    result = []
    wanted = os.path.realpath(WORKER_BINARY)
    for pid in all_pids():
        if process_exe(pid) == wanted:
            result.append(pid)
    return result


def flask_pids():
    result = []
    for pid in all_pids():
        cmd = process_cmdline(pid)
        joined = " ".join(cmd)
        if any(arg.endswith("app.py") for arg in cmd) or ("flask" in joined and "8080" in joined):
            result.append(pid)
    return result


def kill_pids(pids):
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline:
        if not any(os.path.exists(f"/proc/{pid}") for pid in pids):
            return
        time.sleep(0.05)


def post_json(payload, timeout=3):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8080/ingest",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, json.loads(response.read().decode())


def wait_until(predicate, timeout=15, interval=0.1):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except Exception as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise AssertionError(f"Condition was not met: {last_error}")
    raise AssertionError("Condition was not met before timeout")


@pytest.fixture(scope="session", autouse=True)
def live_pipeline():
    assert os.path.isfile(WORKER_SOURCE), "Missing /home/user/etl_worker.cpp"
    assert os.path.isfile(WORKER_BINARY), "Missing compiled /home/user/etl_worker"
    assert os.access(WORKER_BINARY, os.X_OK), "etl_worker is not executable"
    with open(WORKER_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "etl_worker is not a compiled ELF executable"
    assert os.path.isfile(START_SCRIPT), "Missing /home/user/start_all.sh"

    # Remove any pre-existing pipeline and all pre-fabricated output before testing.
    kill_pids(worker_pids())
    kill_pids(flask_pids())
    subprocess.run(["redis-cli", "shutdown", "nosave"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.3)
    subprocess.run(["pkill", "-9", "redis-server"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)

    os.makedirs("/home/user/etl_output", exist_ok=True)
    for path in (CLEAN_JSONL_PATH, REJECTED_JSONL_PATH):
        with open(path, "w"):
            pass

    result = subprocess.run(["bash", START_SCRIPT], cwd="/home/user", timeout=12,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert result.returncode == 0, "start_all.sh did not complete successfully"

    r = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True,
                    socket_connect_timeout=1, socket_timeout=1)
    wait_until(lambda: r.ping(), timeout=12)
    wait_until(lambda: worker_pids(), timeout=12)
    wait_until(lambda: flask_pids(), timeout=12)

    def api_ready():
        try:
            status, _ = post_json({"transaction_id": "readiness", "amount": None})
            return status == 200
        except Exception:
            return False

    wait_until(api_ready, timeout=12)
    wait_until(lambda: "readiness" in load_jsonl(REJECTED_JSONL_PATH), timeout=8)

    # Stop the worker briefly and prove that Flask really queues the raw payload in Redis.
    kill_pids(worker_pids())
    r.delete("etl:input")
    queue_probe = {
        "transaction_id": "queue-" + uuid.uuid4().hex,
        "user_id": "queue-user",
        "amount": 12.75,
        "marker": uuid.uuid4().hex,
        "nested": {"preserve": [1, True, "x"]},
    }
    status, response = post_json(queue_probe)
    assert status == 200 and response.get("status") == "queued"
    wait_until(lambda: r.llen("etl:input") == 1, timeout=5)
    queued = json.loads(r.lindex("etl:input", 0))
    assert queued == queue_probe, "Flask did not preserve and queue the submitted JSON"
    r.lpop("etl:input")

    # Execute the submitted artifact directly so the behavioral test cannot pass on files alone.
    subprocess.Popen([WORKER_BINARY], cwd="/home/user", stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    wait_until(lambda: worker_pids(), timeout=8)

    # Clear the readiness record; all records below must be newly produced by this run.
    for path in (CLEAN_JSONL_PATH, REJECTED_JSONL_PATH):
        with open(path, "w"):
            pass
    r.delete("etl:input")

    clean_payloads = []
    evil_payloads = []

    for fname in sorted(os.listdir(CLEAN_CORPUS_DIR)):
        if fname.endswith(".json"):
            with open(os.path.join(CLEAN_CORPUS_DIR, fname)) as f:
                clean_payloads.append(json.load(f))

    # Random IDs and markers prevent a fixed-output submission from anticipating the test.
    nonce = uuid.uuid4().hex
    for i in range(75):
        clean_payloads.append({
            "transaction_id": f"live-clean-{nonce}-{i}",
            "user_id": f"live-user-{i}",
            "amount": 100.5,
            "marker": nonce,
            "sequence": i,
            "nested": {"values": [i, "keep-me"], "ok": True},
        })

    missing_user_id = f"live-impute-missing-{nonce}"
    null_user_id = f"live-impute-null-{nonce}"
    clean_payloads.extend([
        {"transaction_id": missing_user_id, "amount": 100.5, "marker": nonce},
        {"transaction_id": null_user_id, "user_id": None, "amount": 100.5, "marker": nonce},
    ])

    for fname in sorted(os.listdir(EVIL_CORPUS_DIR)):
        if fname.endswith(".json"):
            with open(os.path.join(EVIL_CORPUS_DIR, fname)) as f:
                evil_payloads.append(json.load(f))

    dynamic_rejected = [
        {"transaction_id": f"live-outlier-{nonce}", "user_id": "attacker", "amount": 999999999.0, "marker": nonce},
        {"transaction_id": f"live-missing-{nonce}", "user_id": "bad", "marker": nonce},
        {"transaction_id": f"live-null-{nonce}", "user_id": "bad", "amount": None, "marker": nonce},
        {"transaction_id": f"live-string-{nonce}", "user_id": "bad", "amount": "100.5", "marker": nonce},
        {"transaction_id": f"live-object-{nonce}", "user_id": "bad", "amount": {"value": 100.5}, "marker": nonce},
    ]
    evil_payloads.extend(dynamic_rejected)

    for payload in clean_payloads + evil_payloads:
        status, response = post_json(payload)
        assert status == 200, f"API rejected transaction {payload.get('transaction_id')}"
        assert response.get("status") == "queued"

    expected_ids = {p["transaction_id"] for p in clean_payloads + evil_payloads}

    def processing_finished():
        clean = load_jsonl(CLEAN_JSONL_PATH)
        rejected = load_jsonl(REJECTED_JSONL_PATH)
        return expected_ids.issubset(set(clean) | set(rejected)) and r.llen("etl:input") == 0

    wait_until(processing_finished, timeout=35, interval=0.2)

    clean = load_jsonl(CLEAN_JSONL_PATH)
    rejected = load_jsonl(REJECTED_JSONL_PATH)
    expected_clean = {p["transaction_id"] for p in clean_payloads}
    expected_rejected = {p["transaction_id"] for p in evil_payloads}

    assert expected_clean.issubset(clean), "Some valid live transactions were not accepted"
    assert expected_clean.isdisjoint(rejected), "Valid live transactions were also rejected"
    assert expected_rejected.issubset(rejected), "Malformed or outlier live transactions bypassed filtering"
    assert expected_rejected.isdisjoint(clean), "Rejected live transactions were also written as clean"

    rich = clean[f"live-clean-{nonce}-25"]
    original = clean_payloads[125]
    assert rich == original, "Accepted JSON properties were not preserved"
    assert clean[missing_user_id].get("user_id") == "UNKNOWN"
    assert clean[null_user_id].get("user_id") == "UNKNOWN"
    assert worker_pids(), "The C++ worker is no longer running"
    assert flask_pids(), "The Flask API is no longer running"
    assert r.ping(), "Redis is no longer running"

    yield


def test_output_directories_and_files_exist():
    assert os.path.isdir("/home/user/etl_output/"), "The directory /home/user/etl_output/ was not created."
    assert os.path.isfile(CLEAN_JSONL_PATH) or os.path.isfile(REJECTED_JSONL_PATH), "Neither clean.jsonl nor rejected.jsonl were created."


def test_clean_corpus_accepted():
    clean_jsonl = load_jsonl(CLEAN_JSONL_PATH)

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, "No clean corpus files found to test."

    bypassed = []
    for fname in clean_files:
        with open(os.path.join(CLEAN_CORPUS_DIR, fname), 'r') as f:
            data = json.load(f)

        tid = data.get('transaction_id')
        if tid not in clean_jsonl:
            bypassed.append(fname)

    assert not bypassed, f"{len(bypassed)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(bypassed)}"


def test_evil_corpus_rejected():
    rejected_jsonl = load_jsonl(REJECTED_JSONL_PATH)

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, "No evil corpus files found to test."

    bypassed = []
    for fname in evil_files:
        with open(os.path.join(EVIL_CORPUS_DIR, fname), 'r') as f:
            data = json.load(f)

        tid = data.get('transaction_id')
        if tid not in rejected_jsonl:
            bypassed.append(fname)

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
