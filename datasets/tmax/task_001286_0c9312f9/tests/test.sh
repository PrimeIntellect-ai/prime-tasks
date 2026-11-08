#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import math
import os
import random
import secrets
import subprocess
import tempfile

import pytest

PIPELINE_DIR = "/home/user/pipeline"


def run(cmd, cwd=None, timeout=120):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def test_vendor_fixed():
    csv_go_path = "/app/vendor/gocsv/csv.go"
    assert os.path.isfile(csv_go_path), f"File {csv_go_path} is missing."
    with open(csv_go_path, "r") as f:
        content = f.read()
    assert 'panic("UNAUTHORIZED MODIFICATION")' not in content, f"Perturbation still exists in {csv_go_path}."

    result = run(["go", "test", "."], cwd="/app/vendor/gocsv")
    assert result.returncode == 0, f"Vendored gocsv does not build or pass its package tests:\n{result.stdout}\n{result.stderr}"


def test_pipeline_artifact_and_module_replacement():
    main_go = os.path.join(PIPELINE_DIR, "main.go")
    go_mod = os.path.join(PIPELINE_DIR, "go.mod")
    assert os.path.isfile(main_go), f"File {main_go} is missing."
    assert os.path.isfile(go_mod), f"File {go_mod} is missing."

    module = run(["go", "list", "-m", "-json", "github.com/gocarina/gocsv"], cwd=PIPELINE_DIR)
    assert module.returncode == 0, f"gocsv is not a module dependency:\n{module.stdout}\n{module.stderr}"
    info = json.loads(module.stdout)
    replacement = info.get("Replace")
    assert replacement and replacement.get("Dir"), "go.mod has no active replacement for github.com/gocarina/gocsv"
    assert os.path.realpath(replacement["Dir"]) == "/app/vendor/gocsv", "gocsv replacement does not point to /app/vendor/gocsv"

    deps = run(["go", "list", "-deps", "."], cwd=PIPELINE_DIR)
    assert deps.returncode == 0, f"Pipeline dependencies cannot be listed:\n{deps.stdout}\n{deps.stderr}"
    assert "github.com/gocarina/gocsv" in deps.stdout.splitlines(), "The pipeline does not use the replaced gocsv package"

    build = run(["go", "build", "-o", "/tmp/pipeline-under-test", "main.go"], cwd=PIPELINE_DIR)
    assert build.returncode == 0, f"Pipeline does not build:\n{build.stdout}\n{build.stderr}"


def test_adversarial_corpus_validate():
    clean_corpus_path = "/home/user/data/clean_corpus"
    evil_corpus_path = "/home/user/data/evil_corpus"
    pipeline_dir = "/home/user/pipeline"

    assert os.path.isdir(clean_corpus_path), f"Clean corpus directory {clean_corpus_path} is missing."
    assert os.path.isdir(evil_corpus_path), f"Evil corpus directory {evil_corpus_path} is missing."
    assert os.path.isdir(pipeline_dir), f"Pipeline directory {pipeline_dir} is missing."

    clean_files = glob.glob(os.path.join(clean_corpus_path, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_corpus_path, "*.csv"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    evil_failures = []

    for f in clean_files:
        result = subprocess.run(
            ["go", "run", "main.go", "validate", f],
            cwd=pipeline_dir,
            capture_output=True
        )
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    for f in evil_files:
        result = subprocess.run(
            ["go", "run", "main.go", "validate", f],
            cwd=pipeline_dir,
            capture_output=True
        )
        if result.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    assert not error_messages, " | ".join(error_messages)


def write_csv(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "sensor_id", "value", "notes"])
        writer.writerows(rows)


def test_runtime_generated_validate_cases():
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix=f"telemetry-{token}-") as td:
        clean_path = os.path.join(td, secrets.token_hex(6) + ".csv")
        clean_rows = [
            ["2031-04-05T06:07:08Z", f"sensor_{token}", "12.75", "ordinary, quoted note"],
            ["2031-04-05T06:08:08Z", f"sensor_{token}_2", "0.25", "space before =formula"],
            ["2031-04-05T06:09:08Z", "sensor_safe", "9.5", "A" * 500],
        ]
        write_csv(clean_path, clean_rows)
        clean = run(["/tmp/pipeline-under-test", "validate", clean_path])
        assert clean.returncode == 0, f"Generated clean CSV was rejected: {clean.stdout}\n{clean.stderr}"

        evil_rows = [
            ["=2031-04-05T06:07:08Z", "sensor", "1.0", "ordinary"],
            ["2031-04-05T06:07:08Z", "+sensor", "1.0", "ordinary"],
            ["2031-04-05T06:07:08Z", "sensor", "-1.0", "ordinary"],
            ["2031-04-05T06:07:08Z", "sensor", "1.0", "@hidden-command"],
            ["2031-04-05T06:07:08Z", "sensor", "1.0", f"before\x00after-{token}"],
            ["2031-04-05T06:07:08Z", "sensor", "1.0", "Z" * 501],
        ]
        random.SystemRandom().shuffle(evil_rows)
        for index, row in enumerate(evil_rows):
            path = os.path.join(td, f"{secrets.token_hex(5)}-{index}.csv")
            write_csv(path, [row])
            result = run(["/tmp/pipeline-under-test", "validate", path])
            assert result.returncode == 1, f"Generated malicious CSV case {index} was not rejected: {result.stdout}\n{result.stderr}"


def test_runtime_generated_transform_and_rolling_averages():
    token = secrets.token_hex(6)
    sensor_a = "alpha_" + token
    sensor_b = "beta_" + token
    offset = random.SystemRandom().randint(1, 40)
    rows = [
        ["2032-07-01T00:00:00Z", sensor_a, str(offset + 10), "first, safe"],
        ["2032-07-01T00:01:00Z", sensor_b, str(offset + 100), "safe"],
        ["2032-07-01T00:02:00Z", sensor_a, str(offset + 20), "safe"],
        ["2032-07-01T00:03:00Z", sensor_a, str(offset + 40), "safe"],
        ["2032-07-01T00:04:00Z", sensor_b, str(offset + 80), "safe"],
        ["2032-07-01T00:05:00Z", sensor_a, str(offset + 70), "safe"],
        ["2032-07-01T00:06:00Z", sensor_b, str(offset + 50), "safe"],
    ]
    expected_averages = [
        offset + 10,
        offset + 100,
        offset + 15,
        offset + 70 / 3,
        offset + 90,
        offset + 130 / 3,
        offset + 230 / 3,
    ]

    with tempfile.TemporaryDirectory(prefix=f"transform-{token}-") as td:
        input_path = os.path.join(td, secrets.token_hex(5) + ".csv")
        output_path = os.path.join(td, secrets.token_hex(5) + ".json")
        write_csv(input_path, rows)

        result = run(["/tmp/pipeline-under-test", "transform", input_path, output_path])
        assert result.returncode == 0, f"transform failed: {result.stdout}\n{result.stderr}"
        assert os.path.isfile(output_path), "transform did not create the requested output file"

        with open(output_path, encoding="utf-8") as f:
            data = json.load(f)
        assert isinstance(data, list), "Transform output must be a JSON array"
        assert len(data) == len(rows), "Transform output has the wrong number of objects"

        required_keys = {"timestamp", "sensor_id", "original_value", "rolling_avg"}
        for index, (obj, source, expected_avg) in enumerate(zip(data, rows, expected_averages)):
            assert isinstance(obj, dict), f"Output item {index} is not an object"
            assert set(obj.keys()) == required_keys, f"Output item {index} has incorrect fields"
            assert obj["timestamp"] == source[0], f"Timestamp/order mismatch at item {index}"
            assert obj["sensor_id"] == source[1], f"Sensor/order mismatch at item {index}"
            assert isinstance(obj["original_value"], (int, float)) and not isinstance(obj["original_value"], bool)
            assert isinstance(obj["rolling_avg"], (int, float)) and not isinstance(obj["rolling_avg"], bool)
            assert math.isclose(float(obj["original_value"]), float(source[2]), rel_tol=1e-12, abs_tol=1e-12)
            assert math.isclose(float(obj["rolling_avg"]), expected_avg, rel_tol=1e-9, abs_tol=1e-9), f"Wrong rolling average at item {index}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
