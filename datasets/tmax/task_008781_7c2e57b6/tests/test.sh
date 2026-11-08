#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import shlex
import stat
import subprocess
import time

import pytest

PIPELINE = "/home/user/pipeline"
RAW = os.path.join(PIPELINE, "raw_metrics.csv")
WEIGHTS = os.path.join(PIPELINE, "model_weights.json")
PRIORS = os.path.join(PIPELINE, "priors.json")
ANOMALIES = os.path.join(PIPELINE, "anomalies.txt")
BENCHMARK = os.path.join(PIPELINE, "benchmark.txt")
PROTECTED = {RAW, WEIGHTS, PRIORS, ANOMALIES, BENCHMARK}


def test_anomalies_output():
    anomalies_file = "/home/user/pipeline/anomalies.txt"
    assert os.path.isfile(anomalies_file), f"Expected file {anomalies_file} does not exist."

    with open(anomalies_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_anomalies = ["REQ003", "REQ005", "REQ006"]

    assert len(lines) == 3, f"Expected exactly 3 anomalies, but found {len(lines)}."
    assert lines == expected_anomalies, f"Anomalies do not match expected output. Got {lines}, expected {expected_anomalies}."


def test_benchmark_output():
    benchmark_file = "/home/user/pipeline/benchmark.txt"
    assert os.path.isfile(benchmark_file), f"Expected file {benchmark_file} does not exist."

    with open(benchmark_file, "r") as f:
        content = f.read().strip()

    assert content, f"File {benchmark_file} is empty."

    try:
        benchmark_val = float(content)
    except ValueError:
        pytest.fail(f"Content of {benchmark_file} is not a valid float: '{content}'")

    assert benchmark_val >= 0, f"Benchmark time should be non-negative, got {benchmark_val}."


def discover_scripts():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in {"__pycache__", "node_modules"}]
        for name in files:
            path = os.path.abspath(os.path.join(root, name))
            if path in PROTECTED:
                continue
            try:
                mode = os.lstat(path).st_mode
                if not stat.S_ISREG(mode):
                    continue
                with open(path, "rb") as f:
                    first = f.readline(256)
            except OSError:
                continue
            script_like = name.endswith((".py", ".sh", ".bash", ".pl", ".rb", ".js"))
            script_like = script_like or first.startswith(b"#!") or bool(mode & 0o111)
            if script_like:
                candidates.append(path)
    return sorted(candidates)


def command_for(path):
    if path.endswith(".py"):
        return ["python3", path]
    if path.endswith((".sh", ".bash")):
        return ["bash", path]
    with open(path, "rb") as f:
        first = f.readline(256).decode("utf-8", "replace").strip()
    if first.startswith("#!"):
        return shlex.split(first[2:].strip()) + [path]
    if os.access(path, os.X_OK):
        return [path]
    return None


def make_case(rng, case_number):
    while True:
        rows = []
        for i in range(11):
            rows.append({
                "request_id": f"H{case_number}_{rng.randrange(100000, 999999)}_{i}",
                "payload_size": rng.randrange(128, 18000),
                "compute_cycles": rng.randrange(100000, 26000000),
            })
        if case_number == 1:
            weights = {"w1": rng.uniform(0.2, 1.1), "w2": rng.uniform(0.3, 1.4), "bias": rng.uniform(-4, 1)}
        else:
            weights = {"w1": rng.uniform(-1.3, -0.2), "w2": rng.uniform(0.25, 1.2), "bias": rng.uniform(-2, 3)}
        logits = [weights["w1"] * (r["payload_size"] / 1024.0) + weights["w2"] * (r["compute_cycles"] / 1000000.0) + weights["bias"] for r in rows]
        if len({round(z, 10) for z in logits}) == len(logits):
            break
    rng.shuffle(rows)
    p_anomaly = rng.uniform(0.01, 0.35)
    priors = {"P_Anomaly": p_anomaly, "P_Normal": 1.0 - p_anomaly}

    scored = []
    for row in rows:
        z = weights["w1"] * (row["payload_size"] / 1024.0) + weights["w2"] * (row["compute_cycles"] / 1000000.0) + weights["bias"]
        if z >= 0:
            likelihood = 1.0 / (1.0 + math.exp(-z))
        else:
            ez = math.exp(z)
            likelihood = ez / (1.0 + ez)
        posterior = (likelihood * priors["P_Anomaly"]) / (likelihood * priors["P_Anomaly"] + (1.0 - likelihood) * priors["P_Normal"])
        scored.append((posterior, row["request_id"]))
    expected = [request_id for _, request_id in sorted(scored, reverse=True)[:3]]
    return rows, weights, priors, expected


def write_case(rows, weights, priors):
    with open(RAW, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["request_id", "payload_size", "compute_cycles"])
        writer.writeheader()
        writer.writerows(rows)
    with open(WEIGHTS, "w") as f:
        json.dump(weights, f)
    with open(PRIORS, "w") as f:
        json.dump(priors, f)
    for path in (ANOMALIES, BENCHMARK):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def validate_generated_outputs(expected, elapsed_ms):
    assert os.path.isfile(ANOMALIES), "The submitted script did not generate anomalies.txt."
    with open(ANOMALIES) as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"Inference result for verifier-generated data was {actual}, expected {expected}."

    assert os.path.isfile(BENCHMARK), "The submitted script did not generate benchmark.txt."
    content = open(BENCHMARK).read().strip()
    assert content, "The submitted script generated an empty benchmark.txt."
    value = float(content)
    assert math.isfinite(value), f"Benchmark must be finite, got {value}."
    assert value > 0, f"Benchmark must report a positive elapsed time, got {value}."
    assert value <= elapsed_ms + 1000.0, f"Reported benchmark {value} ms is not plausible for a run taking {elapsed_ms} ms."


def test_submitted_script_performs_inference():
    candidates = discover_scripts()
    assert candidates, "No submitted inference script was found under /home/user."

    saved = {}
    for path in PROTECTED:
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()
        else:
            saved[path] = None

    rng = random.SystemRandom()
    errors = []
    try:
        cases = [make_case(rng, 1), make_case(rng, 2)]
        for candidate in candidates:
            command = command_for(candidate)
            if not command:
                continue
            candidate_ok = True
            for rows, weights, priors, expected in cases:
                write_case(rows, weights, priors)
                start = time.perf_counter()
                try:
                    result = subprocess.run(
                        command,
                        cwd=PIPELINE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=30,
                        env={**os.environ, "HOME": "/home/user"},
                    )
                    elapsed_ms = (time.perf_counter() - start) * 1000.0
                    assert result.returncode == 0, f"exit code {result.returncode}: {result.stderr[-500:]}"
                    validate_generated_outputs(expected, elapsed_ms)
                except Exception as exc:
                    candidate_ok = False
                    errors.append(f"{candidate}: {exc}")
                    break
            if candidate_ok:
                return
        pytest.fail("No submitted script correctly processed verifier-generated inputs. " + " | ".join(errors[-5:]))
    finally:
        for path, data in saved.items():
            if data is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
