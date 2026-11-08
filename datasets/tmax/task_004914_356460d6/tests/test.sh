#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any fixture services left running by the agent so the verifier can bind
# controlled held-out services to the required ports.
pkill -f 'node /app/fixture/producer.js' 2>/dev/null || true
pkill -f 'python3 /app/fixture/cache.py' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import secrets
import subprocess
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

WORKSPACE = "/home/user/workspace"
STATE = {
    "producer_calls": 0,
    "cache_calls": [],
    "generated_ids": set(),
}
LOCK = threading.Lock()


def legacy_decode(vectors):
    script = r'''const fs = require("fs");
const ecc = require("/app/legacy/ecc.js");
const vectors = JSON.parse(fs.readFileSync(0, "utf8"));
process.stdout.write(JSON.stringify(vectors.map(v => ecc.decode(v.raw_payload, v.ecc_block))));
'''
    proc = subprocess.run(
        ["node", "-e", script],
        input=json.dumps(vectors),
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Could not execute legacy ECC: {proc.stderr}"
    return json.loads(proc.stdout)


# Randomized held-out vectors prevent results.json from being fabricated in advance.
VECTORS = []
for i in range(1000):
    VECTORS.append({
        "id": f"{secrets.token_hex(16)}-{i}",
        "raw_payload": secrets.token_hex(2 + (i % 31)),
        "ecc_block": secrets.token_hex(1 + (i % 8)),
    })
EXPECTED = legacy_decode(VECTORS)
for vector, corrected in zip(VECTORS, EXPECTED):
    vector["corrected_payload"] = corrected
EXPECTED_BY_ID = {v["id"]: v["corrected_payload"] for v in VECTORS}


class ProducerHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if urllib.parse.urlparse(self.path).path != "/telemetry":
            self.send_error(404)
            return
        with LOCK:
            index = STATE["producer_calls"]
            STATE["producer_calls"] += 1
        if index >= len(VECTORS):
            self.send_error(503, "held-out vector supply exhausted")
            return
        vector = VECTORS[index]
        with LOCK:
            STATE["generated_ids"].add(vector["id"])
        body = json.dumps({
            "id": vector["id"],
            "raw_payload": vector["raw_payload"],
            "ecc_block": vector["ecc_block"],
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class CacheHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/verify":
            self.send_error(404)
            return
        params = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        item_id = params.get("id", [""])[0]
        corrected = params.get("corrected_payload", [""])[0]
        expected = EXPECTED_BY_ID.get(item_id)
        valid = (
            expected is not None
            and item_id in STATE["generated_ids"]
            and isinstance(corrected, str)
            and corrected.lower() == str(expected).lower()
        )
        with LOCK:
            STATE["cache_calls"].append((item_id, corrected, valid))
        body = json.dumps({"status": "ok" if valid else "failed"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class ReusableServer(ThreadingHTTPServer):
    allow_reuse_address = True


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    for name in ("ecc.py", "integration.py", "test_ecc.py"):
        assert os.path.isfile(os.path.join(WORKSPACE, name)), f"Required file {name} is missing."

    with open(os.path.join(WORKSPACE, "ecc.py"), "rb") as submitted, open("/app/legacy/ecc.js", "rb") as legacy:
        assert submitted.read() != legacy.read(), "ecc.py must be a Python translation, not a byte-identical copy."

    producer = ReusableServer(("127.0.0.1", 8081), ProducerHandler)
    cache = ReusableServer(("127.0.0.1", 8083), CacheHandler)
    threads = [
        threading.Thread(target=producer.serve_forever, daemon=True),
        threading.Thread(target=cache.serve_forever, daemon=True),
    ]
    for thread in threads:
        thread.start()

    try:
        # Execute the submitted unit suite as requested by the task.
        unit = subprocess.run(
            [sys.executable, "-m", "pytest", os.path.join(WORKSPACE, "test_ecc.py"), "-q"],
            cwd=WORKSPACE,
            text=True,
            capture_output=True,
            timeout=120,
        )
        assert unit.returncode == 0, f"Submitted unit tests failed:\n{unit.stdout}\n{unit.stderr}"

        # Import and behaviorally compare the Python decoder with the shipped legacy implementation.
        spec = importlib.util.spec_from_file_location("submitted_ecc", os.path.join(WORKSPACE, "ecc.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert callable(getattr(module, "decode", None)), "ecc.py must provide a callable decode function."
        for vector in VECTORS[:50]:
            actual = module.decode(vector["raw_payload"], vector["ecc_block"])
            assert actual == vector["corrected_payload"], (
                f"Python decode disagrees with legacy ECC for raw_payload={vector['raw_payload']} "
                f"and ecc_block={vector['ecc_block']}"
            )

        # A stale/self-reported result must not be considered. The verifier executes integration.py.
        results_path = os.path.join(WORKSPACE, "results.json")
        if os.path.exists(results_path):
            os.remove(results_path)
        run = subprocess.run(
            [sys.executable, os.path.join(WORKSPACE, "integration.py")],
            cwd=WORKSPACE,
            text=True,
            capture_output=True,
            timeout=180,
        )
        assert run.returncode == 0, f"integration.py failed:\n{run.stdout}\n{run.stderr}"
        yield
    finally:
        producer.shutdown()
        cache.shutdown()
        producer.server_close()
        cache.server_close()


def test_required_files_exist():
    """Check that the agent created the required Python files."""
    workspace = "/home/user/workspace"
    expected_files = ["ecc.py", "integration.py", "test_ecc.py", "results.json"]

    for f in expected_files:
        path = os.path.join(workspace, f)
        assert os.path.isfile(path), f"Required file {path} is missing."


def test_integration_really_contacted_and_matched_services():
    results_path = os.path.join(WORKSPACE, "results.json")
    with open(results_path) as f:
        results = json.load(f)

    assert isinstance(results, list)
    assert len(results) >= 500
    assert STATE["producer_calls"] >= 500, "integration.py did not query the producer 500 times."
    assert len(STATE["cache_calls"]) >= 500, "integration.py did not query the cache 500 times."

    calls_by_id = {}
    for item_id, corrected, valid in STATE["cache_calls"]:
        calls_by_id.setdefault(item_id, []).append(valid)

    reported_ids = []
    for item in results:
        assert isinstance(item, dict), "Every result must be a JSON object."
        assert isinstance(item.get("id"), str), "Every result must contain an id string."
        assert item.get("status") in ("success", "failed"), "Invalid result status."
        item_id = item["id"]
        reported_ids.append(item_id)
        assert item_id in STATE["generated_ids"], f"Result id {item_id!r} was not issued by the producer."
        assert item_id in calls_by_id, f"No cache verification was made for result id {item_id!r}."
        actually_valid = any(calls_by_id[item_id])
        assert (item["status"] == "success") == actually_valid, (
            f"Self-reported status for {item_id!r} does not match the cache verification."
        )

    assert len(set(reported_ids)) == len(reported_ids), "Each producer operation must be logged once."


def test_results_json_metric():
    """
    Evaluate the metric threshold based on the agent's generated results.json.
    The agent must have processed at least 500 payloads with an Error Recovery Rate >= 0.95.
    """
    results_path = "/home/user/workspace/results.json"
    assert os.path.isfile(results_path), f"{results_path} is missing."

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse {results_path} as valid JSON.")

    assert isinstance(results, list), "results.json must contain a JSON array."
    assert len(results) >= 500, f"Expected at least 500 results in results.json, got {len(results)}."

    success_count = sum(1 for item in results if item.get("status") == "success")
    total_count = len(results)

    recovery_rate = success_count / total_count

    assert recovery_rate >= 0.95, (
        f"Error Recovery Rate metric failed. "
        f"Threshold: >= 0.95, Actual: {recovery_rate:.4f} "
        f"({success_count}/{total_count} successful verifications)."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
