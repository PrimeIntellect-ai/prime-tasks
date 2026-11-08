#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

PIPELINE = Path("/home/user/pipeline.py")
METRICS = Path("/home/user/artifact_metrics.json")
MODELS = Path("/home/user/models")
BENCHMARK = Path("/home/user/benchmark.py")
REQUIRED_KEYS = {"size_bytes", "latency_ms", "throughput"}


def test_pipeline_script_exists():
    assert PIPELINE.is_file(), "/home/user/pipeline.py does not exist."


def test_artifact_metrics_json_exists_and_valid():
    assert METRICS.is_file(), f"{METRICS} does not exist."

    with METRICS.open("r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{METRICS} does not contain valid JSON.")

    assert isinstance(data, dict), f"JSON root in {METRICS} must be an object (dictionary)."


def test_artifact_metrics_content():
    assert METRICS.is_file(), f"{METRICS} does not exist."

    with METRICS.open("r") as f:
        data = json.load(f)

    expected = {
        "model_fast.bin": {
            "size_bytes": 1500,
            "latency_ms": 44.0,
            "throughput": 1136.36,
        },
        "model_balanced.bin": {
            "size_bytes": 4500,
            "latency_ms": 108.0,
            "throughput": 462.96,
        },
        "model_heavy.bin": {
            "size_bytes": 12000,
            "latency_ms": 255.0,
            "throughput": 196.08,
        },
    }

    assert set(data.keys()) == set(expected.keys()), (
        f"Keys in {METRICS} do not match expected models. Got {list(data.keys())}, "
        f"expected {list(expected.keys())}"
    )

    for model_name, expected_metrics in expected.items():
        actual_metrics = data[model_name]
        assert isinstance(actual_metrics, dict), f"Value for {model_name} is not a JSON object."
        assert set(actual_metrics.keys()) == REQUIRED_KEYS, (
            f"Metrics for {model_name} must contain exactly {sorted(REQUIRED_KEYS)}"
        )

        assert "size_bytes" in actual_metrics, f"Missing 'size_bytes' for {model_name}"
        assert actual_metrics["size_bytes"] == expected_metrics["size_bytes"], f"Incorrect size_bytes for {model_name}"

        assert "latency_ms" in actual_metrics, f"Missing 'latency_ms' for {model_name}"
        assert abs(actual_metrics["latency_ms"] - expected_metrics["latency_ms"]) < 0.01, f"Incorrect latency_ms for {model_name}"

        assert "throughput" in actual_metrics, f"Missing 'throughput' for {model_name}"
        assert abs(actual_metrics["throughput"] - expected_metrics["throughput"]) < 0.01, f"Incorrect throughput for {model_name}"


def test_pipeline_discovers_models_and_invokes_benchmark():
    token = secrets.token_hex(12)
    added_models = [
        MODELS / f"dynamic_{token}_small.bin",
        MODELS / f"dynamic_{token}_large.bin",
    ]
    added_sizes = [2101 + secrets.randbelow(700), 7301 + secrets.randbelow(1200)]
    distractor = MODELS / f"dynamic_{token}.txt"
    log_path = Path(f"/tmp/benchmark_calls_{token}.jsonl")

    benchmark_bytes = BENCHMARK.read_bytes()
    benchmark_mode = stat.S_IMODE(BENCHMARK.stat().st_mode)
    metrics_existed = METRICS.exists()
    metrics_bytes = METRICS.read_bytes() if metrics_existed else None

    try:
        for path, size in zip(added_models, added_sizes):
            path.write_bytes(os.urandom(size))
        distractor.write_text("not a model", encoding="utf-8")

        wrapper = f'''import json
import os
import sys

if len(sys.argv) != 2:
    sys.exit(1)
model_path = sys.argv[1]
if not os.path.isabs(model_path) or not os.path.isfile(model_path):
    sys.exit(1)
with open({str(log_path)!r}, "a", encoding="utf-8") as call_log:
    call_log.write(json.dumps(model_path) + "\\n")
size = os.path.getsize(model_path)
filename = os.path.basename(model_path)
latency = (size * 0.02) + len(filename)
throughput = 50000.0 / latency if latency > 0 else 0
print(json.dumps({{
    "latency_ms": round(latency, 2),
    "throughput": round(throughput, 2)
}}))
'''
        BENCHMARK.write_text(wrapper, encoding="utf-8")
        os.chmod(BENCHMARK, benchmark_mode)

        completed = subprocess.run(
            ["python3", str(PIPELINE)],
            cwd="/tmp",
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert completed.returncode == 0, (
            f"pipeline.py failed with exit code {completed.returncode}. "
            f"stdout: {completed.stdout!r}; stderr: {completed.stderr!r}"
        )
        assert METRICS.is_file(), "pipeline.py did not generate /home/user/artifact_metrics.json"

        with METRICS.open("r", encoding="utf-8") as f:
            data = json.load(f)
        assert isinstance(data, dict), "Generated report must be a JSON object"

        model_paths = sorted(MODELS.glob("*.bin"), key=lambda p: p.name)
        expected_names = {p.name for p in model_paths}
        assert set(data.keys()) == expected_names, (
            f"Pipeline did not discover exactly the current .bin files. "
            f"Got {sorted(data.keys())}, expected {sorted(expected_names)}"
        )
        assert distractor.name not in data, "Pipeline included a non-.bin file"

        for path in model_paths:
            size = path.stat().st_size
            latency = round((size * 0.02) + len(path.name), 2)
            throughput = round(50000.0 / latency if latency > 0 else 0, 2)
            actual = data[path.name]
            assert isinstance(actual, dict), f"Value for {path.name} is not a JSON object"
            assert set(actual.keys()) == REQUIRED_KEYS, (
                f"Metrics for {path.name} must contain exactly {sorted(REQUIRED_KEYS)}"
            )
            assert actual["size_bytes"] == size, f"Incorrect size_bytes for {path.name}"
            assert abs(actual["latency_ms"] - latency) < 0.01, f"Incorrect latency_ms for {path.name}"
            assert abs(actual["throughput"] - throughput) < 0.01, f"Incorrect throughput for {path.name}"

        assert log_path.is_file(), "The pipeline did not invoke /home/user/benchmark.py"
        calls = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines() if line]
        expected_calls = {str(path.resolve()) for path in model_paths}
        assert expected_calls.issubset(set(calls)), (
            "The pipeline must invoke /home/user/benchmark.py with the absolute path of every .bin model"
        )
    finally:
        BENCHMARK.write_bytes(benchmark_bytes)
        os.chmod(BENCHMARK, benchmark_mode)
        for path in added_models:
            path.unlink(missing_ok=True)
        distractor.unlink(missing_ok=True)
        log_path.unlink(missing_ok=True)
        if metrics_existed:
            METRICS.write_bytes(metrics_bytes)
        else:
            METRICS.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
