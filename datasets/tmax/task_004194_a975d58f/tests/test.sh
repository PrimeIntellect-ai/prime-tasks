#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_SOLVER="/app/peer_resolver.verifier-real.$$"
LOG_FILE="/tmp/peer_resolver_calls.jsonl"
STATE_FILE="/tmp/peer_resolver_active"

cleanup() {
    if [ -e "$REAL_SOLVER" ]; then
        rm -f /app/peer_resolver
        mv "$REAL_SOLVER" /app/peer_resolver
        chmod +x /app/peer_resolver
    fi
}
trap cleanup EXIT

mv /app/peer_resolver "$REAL_SOLVER"
cat > /app/peer_resolver <<EOF
#!/usr/bin/env python3
import base64
import fcntl
import json
import os
import subprocess
import sys
import time
import uuid

REAL = "$REAL_SOLVER"
LOG = "$LOG_FILE"
STATE = "$STATE_FILE"
call_id = uuid.uuid4().hex


def change_active(delta):
    with open(STATE, "r+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        raw = f.read().strip()
        active = int(raw or "0")
        before = active
        active += delta
        f.seek(0)
        f.truncate()
        f.write(str(active))
        f.flush()
        return before


def log_event(event):
    with open(LOG, "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps(event, sort_keys=True) + "\\n")
        f.flush()

args = sys.argv[1:]
encoded = []
for path in args:
    try:
        with open(path, "rb") as f:
            encoded.append(base64.b64encode(f.read()).decode("ascii"))
    except Exception as exc:
        encoded.append({"error": repr(exc)})

active_before = change_active(1)
start_ns = time.monotonic_ns()
log_event({
    "event": "start",
    "id": call_id,
    "pid": os.getpid(),
    "time_ns": start_ns,
    "active_before": active_before,
    "args": args,
    "contents_b64": encoded,
})

try:
    # A measurable delay lets the verifier check that avg_time_ms reflects the
    # executions rather than being an arbitrary constant such as zero.
    time.sleep(0.020)
    result = subprocess.run([REAL] + args, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    sys.stdout.buffer.write(result.stdout)
    sys.stdout.buffer.flush()
    sys.stderr.buffer.write(result.stderr)
    sys.stderr.buffer.flush()
    rc = result.returncode
finally:
    end_ns = time.monotonic_ns()
    before_end = change_active(-1)
    log_event({
        "event": "end",
        "id": call_id,
        "pid": os.getpid(),
        "time_ns": end_ns,
        "active_before_decrement": before_end,
    })

sys.exit(rc)
EOF
chmod 755 /app/peer_resolver
: > "$LOG_FILE"
echo 0 > "$STATE_FILE"
chmod 666 "$LOG_FILE" "$STATE_FILE"

export VERIFIER_REAL_SOLVER="$REAL_SOLVER"
export VERIFIER_CALL_LOG="$LOG_FILE"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import math
import os
import subprocess
import tempfile
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
REAL_SOLVER = os.environ["VERIFIER_REAL_SOLVER"]
CALL_LOG = os.environ["VERIFIER_CALL_LOG"]


def clear_calls():
    with open(CALL_LOG, "w"):
        pass


def read_calls():
    with open(CALL_LOG) as f:
        return [json.loads(line) for line in f if line.strip()]


def completed_calls():
    events = read_calls()
    starts = {e["id"]: e for e in events if e["event"] == "start"}
    ends = {e["id"]: e for e in events if e["event"] == "end"}
    assert starts.keys() == ends.keys(), "Every solver execution must complete"
    return [(starts[key], ends[key]) for key in starts]


def oracle_patch(graph_data, manifest_data):
    with tempfile.TemporaryDirectory() as td:
        graph = os.path.join(td, "graph.bin")
        manifest = os.path.join(td, "manifest.json")
        with open(graph, "wb") as f:
            f.write(graph_data)
        with open(manifest, "wb") as f:
            f.write(manifest_data)
        diff = subprocess.run(
            [REAL_SOLVER, graph, manifest], check=True, stdout=subprocess.PIPE
        ).stdout
        applied = subprocess.run(
            ["patch", "-s", manifest], input=diff, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        assert applied.returncode == 0, applied.stderr.decode(errors="replace")
        with open(manifest, "rb") as f:
            return f.read().decode("utf-8")


def post_resolve(graph_data, manifest_data):
    payload = {
        "graph_b64": base64.b64encode(graph_data).decode("utf-8"),
        "manifest_b64": base64.b64encode(manifest_data).decode("utf-8"),
    }
    try:
        response = requests.post(f"{BASE_URL}/resolve", json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to POST /resolve endpoint: {e}")
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        resp_json = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "patched_manifest" in resp_json, (
        "Response JSON missing 'patched_manifest' key."
    )
    return resp_json


def assert_single_resolve_call(graph_data, manifest_data):
    calls = completed_calls()
    assert len(calls) == 1, "POST /resolve must invoke the solver once"
    start, _ = calls[0]
    assert len(start["args"]) == 2
    assert start["contents_b64"] == [
        base64.b64encode(graph_data).decode("ascii"),
        base64.b64encode(manifest_data).decode("ascii"),
    ], "The solver must receive files containing the decoded request values"


def test_01_resolve_endpoint():
    """Retain the original fixed expected-output assertion."""
    graph_data = b"dummy_graph"
    manifest_data = b'{\n  "name": "mobile-app"\n}'
    clear_calls()
    resp_json = post_resolve(graph_data, manifest_data)

    expected_patched = '{\n  "dependencies_resolved": true,\n  "name": "mobile-app"\n}'
    assert resp_json["patched_manifest"] == expected_patched, (
        f"Patched manifest does not match expected output.\n"
        f"Expected:\n{expected_patched}\nGot:\n{resp_json['patched_manifest']}"
    )
    assert_single_resolve_call(graph_data, manifest_data)


def test_02_resolve_uses_each_request():
    # Trailing JSON whitespace yields distinct valid manifests while preserving
    # the context accepted by the supplied solver's patch.
    nonce = os.urandom(18)
    cases = [
        (b"graph-A-" + nonce, b'{\n  "name": "mobile-app"\n}\n '),
        (b"graph-B-" + nonce[::-1], b'{\n  "name": "mobile-app"\n}\n       '),
    ]
    for graph_data, manifest_data in cases:
        expected = oracle_patch(graph_data, manifest_data)
        clear_calls()
        resp_json = post_resolve(graph_data, manifest_data)
        assert resp_json["patched_manifest"] == expected
        assert_single_resolve_call(graph_data, manifest_data)


def test_03_benchmark_endpoint():
    clear_calls()
    started = time.perf_counter()
    try:
        response = requests.get(f"{BASE_URL}/benchmark", timeout=30)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to GET /benchmark endpoint: {e}")
    elapsed_ms = (time.perf_counter() - started) * 1000.0

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        resp_json = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "avg_time_ms" in resp_json, (
        "Response JSON missing 'avg_time_ms' key."
    )
    avg_time = resp_json["avg_time_ms"]
    assert isinstance(avg_time, (int, float)), (
        f"'avg_time_ms' should be a number, got {type(avg_time)}."
    )
    assert avg_time >= 0, (
        f"'avg_time_ms' should be non-negative, got {avg_time}."
    )
    assert math.isfinite(avg_time), "'avg_time_ms' must be finite"

    calls = completed_calls()
    assert len(calls) == 50, (
        f"GET /benchmark must execute the solver exactly 50 times; got {len(calls)}"
    )
    with open("/app/sample_graph.bin", "rb") as f:
        graph_b64 = base64.b64encode(f.read()).decode("ascii")
    with open("/app/sample_manifest.json", "rb") as f:
        manifest_b64 = base64.b64encode(f.read()).decode("ascii")

    durations_ms = []
    for start, end in calls:
        assert start["args"] == [
            "/app/sample_graph.bin", "/app/sample_manifest.json"
        ], "Benchmark used the wrong solver arguments"
        assert start["contents_b64"] == [graph_b64, manifest_b64]
        assert start["active_before"] == 0, (
            "Benchmark solver executions must be sequential, not overlapping"
        )
        assert end["active_before_decrement"] == 1
        durations_ms.append((end["time_ns"] - start["time_ns"]) / 1_000_000)

    measured_inner_avg = sum(durations_ms) / 50.0
    wall_avg = elapsed_ms / 50.0
    assert avg_time > 0, "Reported average cannot be a fabricated zero"
    assert avg_time >= measured_inner_avg - 5.0, (
        f"Reported average {avg_time} ms is below measured execution time "
        f"{measured_inner_avg:.3f} ms"
    )
    assert avg_time <= wall_avg + 10.0, (
        f"Reported average {avg_time} ms is inconsistent with endpoint wall "
        f"time ({wall_avg:.3f} ms per execution)"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
