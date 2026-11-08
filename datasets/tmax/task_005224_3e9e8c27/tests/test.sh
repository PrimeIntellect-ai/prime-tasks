#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile
import pytest


def compute_expected_predictions():
    features_path = "/home/user/data/features.csv"
    metadata_path = "/home/user/data/metadata.csv"
    weights_path = "/home/user/models/v2_weights.txt"

    # Read weights
    with open(weights_path, "r") as f:
        w1, w2, w3, b = map(float, f.read().strip().split(","))

    # Read features
    features = {}
    with open(features_path, "r") as f:
        lines = f.read().strip().split("\n")[1:]  # skip header
        for line in lines:
            parts = line.split(",")
            features[parts[0]] = list(map(float, parts[1:]))

    # Read metadata
    metadata = {}
    with open(metadata_path, "r") as f:
        lines = f.read().strip().split("\n")[1:]  # skip header
        for line in lines:
            parts = line.split(",")
            metadata[parts[0]] = parts[2]  # model_version

    # Compute predictions
    predictions = {}
    for pid in features:
        if pid in metadata and metadata[pid] == "v2":
            f1, f2, f3 = features[pid]
            val = w1*f1 + w2*f2 + w3*f3 + b
            predictions[pid] = max(0.0, val)

    return predictions


def test_pipeline_execution_and_output():
    script_path = "/home/user/run_pipeline.sh"
    cpp_path = "/home/user/infer.cpp"

    assert os.path.exists(cpp_path), f"Missing C++ file at {cpp_path}"
    assert os.path.exists(script_path), f"Missing script at {script_path}"

    # Run the pipeline
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"run_pipeline.sh failed with exit code {result.returncode}. stderr: {result.stderr}"

    predictions_path = "/home/user/predictions.csv"
    summary_path = "/home/user/summary.txt"

    assert os.path.exists(predictions_path), f"Predictions file not found at {predictions_path}"
    assert os.path.exists(summary_path), f"Summary file not found at {summary_path}"

    expected_preds = compute_expected_predictions()

    # Read actual predictions
    actual_preds = {}
    with open(predictions_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            assert len(parts) == 2, f"Invalid prediction format: {line}"
            actual_preds[parts[0]] = float(parts[1])

    # Check predictions
    assert set(actual_preds.keys()) == set(expected_preds.keys()), "Prediction IDs do not match expected 'v2' rows."

    for pid, exp_val in expected_preds.items():
        act_val = actual_preds[pid]
        assert abs(act_val - exp_val) < 1e-4, f"Prediction for ID {pid} is {act_val}, expected {exp_val:.4f}"

    # Check summary
    expected_avg = sum(expected_preds.values()) / len(expected_preds)

    with open(summary_path, "r") as f:
        summary_content = f.read().strip()

    try:
        actual_avg = float(summary_content)
    except ValueError:
        pytest.fail(f"Summary file does not contain a valid float: {summary_content}")

    assert abs(actual_avg - expected_avg) < 1e-4, f"Summary average is {actual_avg}, expected {expected_avg:.4f}"


def test_infer_cpp_compiles_and_handles_unseen_inputs():
    cpp_path = "/home/user/infer.cpp"
    assert os.path.isfile(cpp_path), f"Missing C++ file at {cpp_path}"

    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "infer_test")
        weights_path = os.path.join(td, "weights.txt")

        build = subprocess.run(
            ["g++", "-std=c++17", cpp_path, "-o", binary],
            capture_output=True, text=True, timeout=30
        )
        assert build.returncode == 0, f"infer.cpp does not compile as C++17: {build.stderr}"
        assert os.path.isfile(binary) and os.access(binary, os.X_OK)

        weights = [rng.randint(-25, 25) / 10.0 for _ in range(4)]
        if weights[:3] == [0.0, 0.0, 0.0]:
            weights[0] = 1.3
        with open(weights_path, "w") as f:
            f.write(",".join(str(x) for x in weights) + "\n")

        rows = []
        expected = {}
        for i in range(9):
            pid = str(rng.randint(100000, 999999) + i)
            vals = [rng.randint(-40, 40) / 10.0 for _ in range(3)]
            timestamp = str(rng.randint(1600000000, 1900000000))
            version = rng.choice(["v1", "v2", "v20", "custom"])
            rows.append(",".join([pid] + [str(x) for x in vals] + [timestamp, version]))
            raw = sum(weights[j] * vals[j] for j in range(3)) + weights[3]
            expected[pid] = max(0.0, raw)

        run = subprocess.run(
            [binary, weights_path], input="\n".join(rows) + "\n",
            capture_output=True, text=True, timeout=10
        )
        assert run.returncode == 0, f"Compiled inference engine failed: {run.stderr}"
        output_lines = run.stdout.splitlines()
        assert len(output_lines) == len(rows), "Inference engine did not emit exactly one line per input row"

        seen = set()
        for line in output_lines:
            assert re.fullmatch(r"[^,\r\n]+,-?\d+\.\d{4}", line), f"Invalid id,prediction format: {line!r}"
            pid, value_text = line.split(",")
            assert pid in expected and pid not in seen
            seen.add(pid)
            assert abs(float(value_text) - expected[pid]) <= 0.000051, \
                f"Incorrect prediction for unseen input {pid}"
        assert seen == set(expected)


def test_pipeline_joins_filters_and_infers_on_unseen_data():
    script_path = "/home/user/run_pipeline.sh"
    paths = [
        "/home/user/data/features.csv",
        "/home/user/data/metadata.csv",
        "/home/user/models/v2_weights.txt",
    ]
    rng = random.SystemRandom()
    originals = {path: open(path, "rb").read() for path in paths}

    base = rng.randint(20000, 80000)
    ids = [str(base + i) for i in range(8)]
    feature_values = {
        ids[i]: [rng.randint(-35, 35) / 10.0 for _ in range(3)]
        for i in range(7)
    }
    versions = {
        ids[0]: "v2",
        ids[1]: "v1",
        ids[2]: "v2",
        ids[3]: "v20",
        ids[4]: "v2",
        ids[5]: "v2",
        ids[7]: "v2",  # metadata-only row must not appear
    }
    weights = [rng.randint(-20, 20) / 10.0 for _ in range(4)]
    if weights[:3] == [0.0, 0.0, 0.0]:
        weights[1] = -1.7

    feature_order = list(feature_values)
    metadata_order = list(versions)
    rng.shuffle(feature_order)
    rng.shuffle(metadata_order)

    try:
        with open(paths[0], "w") as f:
            f.write("id,f1,f2,f3\n")
            for pid in feature_order:
                f.write(pid + "," + ",".join(str(x) for x in feature_values[pid]) + "\n")
        with open(paths[1], "w") as f:
            f.write("id,timestamp,model_version\n")
            for index, pid in enumerate(metadata_order):
                f.write(f"{pid},{1700000000 + index},{versions[pid]}\n")
        with open(paths[2], "w") as f:
            f.write(",".join(str(x) for x in weights) + "\n")

        infer_path = "/home/user/infer"
        if os.path.lexists(infer_path):
            if os.path.isdir(infer_path) and not os.path.islink(infer_path):
                shutil.rmtree(infer_path)
            else:
                os.unlink(infer_path)

        result = subprocess.run(["bash", script_path], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"Pipeline failed on unseen data: {result.stderr}"
        assert os.path.isfile(infer_path) and os.access(infer_path, os.X_OK), \
            "Pipeline did not create the required executable /home/user/infer"
        with open(infer_path, "rb") as f:
            assert f.read(4) == b"\x7fELF", "/home/user/infer is not a compiled executable"

        expected = {}
        for pid, vals in feature_values.items():
            if versions.get(pid) == "v2":
                expected[pid] = max(0.0, sum(weights[j] * vals[j] for j in range(3)) + weights[3])

        with open("/home/user/predictions.csv") as f:
            lines = [line.rstrip("\n") for line in f if line.strip()]
        assert len(lines) == len(expected)
        actual = {}
        for line in lines:
            assert re.fullmatch(r"[^,\r\n]+,-?\d+\.\d{4}", line), f"Invalid prediction format: {line!r}"
            pid, value_text = line.split(",")
            assert pid not in actual, f"Duplicate prediction ID: {pid}"
            actual[pid] = float(value_text)
        assert set(actual) == set(expected), "Pipeline did not perform the required join and exact-v2 filter"
        for pid, value in expected.items():
            assert abs(actual[pid] - value) <= 0.000051, f"Wrong dynamic prediction for {pid}"

        with open("/home/user/summary.txt") as f:
            summary = f.read().strip()
        assert re.fullmatch(r"-?\d+\.\d{4}", summary), "Summary is not formatted to exactly four decimal places"
        expected_summary = sum(actual.values()) / len(actual)
        assert abs(float(summary) - expected_summary) <= 0.000051

        # Exercise the executable produced by the pipeline directly as well.
        probe_id = str(base + 99)
        probe_vals = [rng.randint(-30, 30) / 10.0 for _ in range(3)]
        probe = f"{probe_id},{probe_vals[0]},{probe_vals[1]},{probe_vals[2]},1800000000,v2\n"
        probe_run = subprocess.run(
            [infer_path, paths[2]], input=probe, capture_output=True, text=True, timeout=10
        )
        assert probe_run.returncode == 0
        assert re.fullmatch(re.escape(probe_id) + r",-?\d+\.\d{4}\n?", probe_run.stdout)
        probe_expected = max(0.0, sum(weights[j] * probe_vals[j] for j in range(3)) + weights[3])
        assert abs(float(probe_run.stdout.strip().split(",")[1]) - probe_expected) <= 0.000051
    finally:
        for path, content in originals.items():
            with open(path, "wb") as f:
                f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
