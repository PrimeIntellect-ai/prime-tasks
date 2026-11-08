#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import secrets
import stat
import subprocess

ANALYZE_PATH = "/home/user/analyze.go"
METRICS_PATH = "/home/user/metrics.jsonl"
SUMMARY_PATH = "/home/user/summary.json"

CANONICAL_INPUT = '''{"model_id": "m1", "features": [0.0, 6.0, 8.0], "latency_ms": 42.5}
{"model_id": "m2", "features": [5.0, 5.0], "latency_ms": 12.0}
{"model_id": "m3", "features": [10.0, 0.0, 0.0], "latency_ms": 30.1}
{"model_id": "m4", "features": "invalid", "latency_ms": 10.0}
{"model_id": "m5", "features": [3.0, 4.0, 0.0], "latency_ms": 15.5}
{"model_id": "m6", "features": [8.0, 8.0, 8.0], "latency_ms": 55.0}
{"model_id": "m7", "features": [0.0, 10.0, 0.0], "latency_ms": 40.0}
{"model_id": "m8", "features": [2.0, 2.0, 2.0], "latency_ms": 8.0}
{"model_id": "m9", "features": [12.0, 5.0, 0.0], "latency_ms": 60.5}
{"model_id": "m10", "features": [1.0, 1.0, 1.0], "latency_ms": "fast"}
{"model_id": "m11", "features": [0.0, 0.0, 15.0], "latency_ms": 48.2}
{"model_id": "m12", "features": [1.0, 2.0, 3.0], "latency_ms": 11.1}
{"model_id": "m13", "features": [6.0, 6.0, 7.0], "latency_ms": 70.0}
{"model_id": "m14", "features": [0.0, 0.0, 0.0], "latency_ms": 5.0}
'''


def expected_from_text(text):
    valid_count = 0
    selected_latencies = []

    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue

        if not isinstance(data, dict):
            continue
        if not all(k in data for k in ("model_id", "features", "latency_ms")):
            continue
        if not isinstance(data["model_id"], str):
            continue
        if not isinstance(data["features"], list) or len(data["features"]) != 3:
            continue
        if any(isinstance(x, bool) or not isinstance(x, (int, float)) for x in data["features"]):
            continue
        if isinstance(data["latency_ms"], bool) or not isinstance(data["latency_ms"], (int, float)):
            continue

        valid_count += 1
        features = [float(x) for x in data["features"]]
        if math.sqrt(sum(x * x for x in features)) >= 10.0:
            selected_latencies.append(float(data["latency_ms"]))

    selected_latencies.sort()
    selected_count = len(selected_latencies)
    expected_p95 = 0.0
    if selected_count:
        idx = int(math.ceil(0.95 * selected_count)) - 1
        expected_p95 = selected_latencies[idx]
    return valid_count, selected_count, expected_p95


def run_and_validate(input_text):
    with open(METRICS_PATH, "w") as f:
        f.write(input_text)
    if os.path.exists(SUMMARY_PATH):
        os.remove(SUMMARY_PATH)

    result = subprocess.run(
        ["go", "run", ANALYZE_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, "analyze.go failed to run:\n" + result.stderr
    assert os.path.exists(SUMMARY_PATH), f"File {SUMMARY_PATH} is missing. The Go script must generate this file."
    assert os.path.exists(METRICS_PATH), f"File {METRICS_PATH} is missing."

    try:
        with open(SUMMARY_PATH, "r") as f:
            summary = json.load(f)
    except json.JSONDecodeError:
        assert False, f"File {SUMMARY_PATH} is not valid JSON."

    assert isinstance(summary, dict), "summary.json must contain a JSON object"
    assert "valid_records" in summary, "Missing 'valid_records' in summary.json"
    assert "selected_records" in summary, "Missing 'selected_records' in summary.json"
    assert "p95_latency" in summary, "Missing 'p95_latency' in summary.json"
    assert set(summary) == {"valid_records", "selected_records", "p95_latency"}, "summary.json has unexpected fields"

    valid_count, selected_count, expected_p95 = expected_from_text(input_text)
    assert isinstance(summary["valid_records"], int) and not isinstance(summary["valid_records"], bool)
    assert isinstance(summary["selected_records"], int) and not isinstance(summary["selected_records"], bool)
    assert isinstance(summary["p95_latency"], (int, float)) and not isinstance(summary["p95_latency"], bool)
    assert summary["valid_records"] == valid_count, f"Expected {valid_count} valid_records, got {summary['valid_records']}"
    assert summary["selected_records"] == selected_count, f"Expected {selected_count} selected_records, got {summary['selected_records']}"
    assert math.isclose(summary["p95_latency"], expected_p95, rel_tol=1e-5, abs_tol=1e-9), f"Expected p95_latency ~{expected_p95}, got {summary['p95_latency']}"


def make_runtime_input():
    rng = random.Random(secrets.randbits(128))
    records = []

    for i in range(24):
        radius = round(rng.uniform(10.0, 35.0), 6)
        latency = round(rng.uniform(1.0, 500.0), 6)
        records.append(json.dumps({"model_id": f"selected-{i}", "features": [radius, 0, 0], "latency_ms": latency}))

    for i in range(7):
        radius = round(rng.uniform(0.0, 9.5), 6)
        latency = round(rng.uniform(1.0, 500.0), 6)
        records.append(json.dumps({"model_id": f"unselected-{i}", "features": [radius, 0, 0], "latency_ms": latency}))

    records.extend([
        '{"features":[10,0,0],"latency_ms":1}',
        '{"model_id":"missing-features","latency_ms":2}',
        '{"model_id":"missing-latency","features":[10,0,0]}',
        '{"model_id":7,"features":[10,0,0],"latency_ms":3}',
        '{"model_id":"short","features":[10,0],"latency_ms":4}',
        '{"model_id":"long","features":[10,0,0,0],"latency_ms":5}',
        '{"model_id":"string-feature","features":["10",0,0],"latency_ms":6}',
        '{"model_id":"bool-feature","features":[true,0,0],"latency_ms":7}',
        '{"model_id":"string-latency","features":[10,0,0],"latency_ms":"8"}',
        '{"model_id":"bool-latency","features":[10,0,0],"latency_ms":true}',
        '["not","an","object"]',
        '{malformed json',
    ])
    rng.shuffle(records)
    return "\n".join(records) + "\n"


def test_analyze_go_and_summary():
    assert os.path.lexists(ANALYZE_PATH), f"File {ANALYZE_PATH} is missing."
    assert stat.S_ISREG(os.lstat(ANALYZE_PATH).st_mode), f"File {ANALYZE_PATH} must be a regular Go source file."

    # Exercise the submitted program on verifier-generated data that the agent
    # could not modify in advance, including malformed and missing-field cases.
    run_and_validate(make_runtime_input())

    # Restore and verify the task's original input and leave its required final
    # summary in place.
    run_and_validate(CANONICAL_INPUT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
