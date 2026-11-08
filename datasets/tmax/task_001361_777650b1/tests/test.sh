#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import tempfile
from collections import Counter

import pandas as pd
import pytest

EXE = "/home/user/bin/config_tracker"
META = "/home/user/data/server_meta.csv"
CHANGES = "/home/user/data/config_changes.jsonl"
OUTPUT = "/home/user/output/anomalies.csv"
SOURCE = "/home/user/src/config_tracker.cpp"


def test_simdjson_fixed():
    """Verify that the deliberate perturbation in simdjson's CMakeLists.txt was fixed."""
    cmake_path = "/app/simdjson/CMakeLists.txt"
    if os.path.isfile(cmake_path):
        with open(cmake_path, "r") as f:
            content = f.read()
        assert "CMAKE_CXX_STANDARD 11" not in content, "simdjson CMakeLists.txt still contains the legacy 'CMAKE_CXX_STANDARD 11' perturbation."


def test_source_and_executable_exist():
    assert os.path.isfile(SOURCE), f"C++ source missing at {SOURCE}"
    assert os.path.isfile(EXE), f"Executable missing at {EXE}"
    assert os.access(EXE, os.X_OK), f"File at {EXE} is not executable."


def derive_expected(meta_path, changes_path):
    limits = {}
    with open(meta_path, newline="") as f:
        for row in csv.DictReader(f):
            limits[row["server_id"]] = int(row["max_changes_per_min"])

    counts = Counter()
    with open(changes_path) as f:
        for line in f:
            try:
                record = json.loads(line)
            except Exception:
                continue
            if not all(k in record for k in ("timestamp", "server_id", "config_key")):
                continue
            timestamp = record["timestamp"]
            server_id = record["server_id"]
            if not isinstance(timestamp, int) or isinstance(timestamp, bool):
                continue
            if timestamp < 1700000000 or server_id not in limits:
                continue
            counts[(server_id, (timestamp // 60) * 60)] += 1

    return {
        (server_id, window_start, count)
        for (server_id, window_start), count in counts.items()
        if count > limits[server_id]
    }


def read_predictions(path):
    assert os.path.isfile(path), f"Output file missing at {path}"
    try:
        pred = pd.read_csv(path)
    except Exception as e:
        pytest.fail(f"Failed to read predictions CSV: {e}")
    assert list(pred.columns) == ["server_id", "window_start", "change_count"], \
        "Output CSV must have exactly: server_id,window_start,change_count"
    try:
        rows = [(str(r.server_id), int(r.window_start), int(r.change_count)) for r in pred.itertuples(index=False)]
    except Exception as e:
        pytest.fail(f"Invalid output values: {e}")
    assert len(rows) == len(set(rows)), "Output contains duplicate anomaly rows"
    return set(rows)


def test_execute_and_f1_score():
    """Run the submitted program and score output against independently derived aligned windows."""
    expected = derive_expected(META, CHANGES)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run([EXE], cwd="/home/user", stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=30)
    assert result.returncode == 0, f"config_tracker failed: {result.stderr}"
    predicted = read_predictions(OUTPUT)

    pred_keys = {(s, w) for s, w, _ in predicted}
    truth_keys = {(s, w) for s, w, _ in expected}
    tp = len(pred_keys & truth_keys)
    fp = len(pred_keys - truth_keys)
    fn = len(truth_keys - pred_keys)
    precision = tp / (tp + fp) if tp + fp else 0
    recall = tp / (tp + fn) if tp + fn else 0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0
    assert f1 >= 0.98, f"F1 Score {f1:.4f} is below 0.98"
    assert predicted == expected, "Anomaly change_count values are incorrect"


def test_fresh_held_out_input():
    """Exercise the executable on fresh data so a precomputed CSV cannot pass."""
    meta_backup = open(META, "rb").read()
    changes_backup = open(CHANGES, "rb").read()
    try:
        with open(META, "w", newline="") as f:
            f.write("server_id,tier,max_changes_per_min\nnode-x,edge,2\nnode-y,db,1\n")
        records = [
            {"timestamp": 1700000039, "server_id": "node-x", "config_key": "a"},
            {"timestamp": 1700000040, "server_id": "node-x", "config_key": "a"},
            {"timestamp": 1700000041, "server_id": "node-x", "config_key": "b"},
            {"timestamp": 1700000099, "server_id": "node-x", "config_key": "c"},
            {"timestamp": 1700000100, "server_id": "node-y", "config_key": "a"},
            {"timestamp": 1700000101, "server_id": "node-y", "config_key": "b"},
            {"timestamp": 1699999999, "server_id": "node-y", "config_key": "bad"},
            {"timestamp": 1700000102, "server_id": "unknown", "config_key": "bad"},
            {"timestamp": 1700000102, "server_id": "node-y"},
        ]
        with open(CHANGES, "w") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")
            f.write("not json\n")
        expected = derive_expected(META, CHANGES)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        result = subprocess.run([EXE], cwd="/home/user", stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, timeout=30)
        assert result.returncode == 0, f"config_tracker failed on held-out input: {result.stderr}"
        assert read_predictions(OUTPUT) == expected
    finally:
        with open(META, "wb") as f:
            f.write(meta_backup)
        with open(CHANGES, "wb") as f:
            f.write(changes_backup)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
