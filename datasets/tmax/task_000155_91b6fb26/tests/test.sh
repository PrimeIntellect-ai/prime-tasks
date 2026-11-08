#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import configparser
import json
import math
import os
import runpy
import secrets
import subprocess
import sys

PIPELINE = "/home/user/pipeline"


def test_config_updated():
    config_path = "/home/user/pipeline/config.ini"
    assert os.path.isfile(config_path), f"File missing: {config_path}"

    config = configparser.ConfigParser()
    config.read(config_path)

    assert 'Settings' in config, "[Settings] section missing in config.ini"
    assert 'chunk_size' in config['Settings'], "chunk_size missing in config.ini"
    assert config['Settings']['chunk_size'] == '10000', "chunk_size was not updated to 10000"


def test_result_json_correct():
    result_path = "/home/user/pipeline/result.json"
    assert os.path.isfile(result_path), f"File missing: {result_path}"

    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "result.json is not valid JSON"

    assert "naive_sum" in data, "naive_sum missing in result.json"
    assert "precise_sum" in data, "precise_sum missing in result.json"
    assert "corrupted_count" in data, "corrupted_count missing in result.json"

    assert data["naive_sum"] == 10000000000001000.0, f"naive_sum incorrect: expected 10000000000001000.0, got {data['naive_sum']}"
    assert data["precise_sum"] == 10000000000002000.0, f"precise_sum incorrect: expected 10000000000002000.0, got {data['precise_sum']}"
    assert data["corrupted_count"] == 50, f"corrupted_count incorrect: expected 50, got {data['corrupted_count']}"


def test_regression_test_file():
    test_path = "/home/user/pipeline/test_precision.py"
    assert os.path.isfile(test_path), f"Regression test file missing: {test_path}"

    with open(test_path, 'r') as f:
        content = f.read()

    assert "test_precision_recovery" in content, "Function 'test_precision_recovery' missing in test_precision.py"
    assert "1e16" in content, "The value '1e16' is missing in test_precision.py"
    assert "math.fsum" in content or "fsum" in content, "math.fsum usage missing in test_precision.py"

    completed = subprocess.run(
        [sys.executable, "-m", "pytest", test_path, "-q", "--tb=short"],
        cwd=PIPELINE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, "test_precision.py did not pass when executed:\n" + completed.stdout

    namespace = runpy.run_path(test_path, run_name="precision_test_normal")
    test_function = namespace.get("test_precision_recovery")
    assert callable(test_function), "test_precision_recovery is not callable"
    test_function()

    original_fsum = math.fsum
    try:
        math.fsum = lambda values: builtins.sum(values)
        mutated_namespace = runpy.run_path(test_path, run_name="precision_test_mutated")
        mutated_test = mutated_namespace.get("test_precision_recovery")
        assert callable(mutated_test), "test_precision_recovery is not callable"
        detected_bad_fsum = False
        try:
            mutated_test()
        except AssertionError:
            detected_bad_fsum = True
        assert detected_bad_fsum, "test_precision_recovery does not detect a naive replacement for math.fsum"
    finally:
        math.fsum = original_fsum


def test_aggregator_executes_on_fresh_input():
    aggregator_path = os.path.join(PIPELINE, "aggregator.py")
    data_path = os.path.join(PIPELINE, "data.csv")
    result_path = os.path.join(PIPELINE, "result.json")

    assert os.path.isfile(aggregator_path), f"File missing: {aggregator_path}"

    with open(data_path, "rb") as f:
        original_data = f.read()
    with open(result_path, "rb") as f:
        original_result = f.read()

    pre_count = 113 + secrets.randbelow(205)
    post_count = 257 + secrets.randbelow(233)
    random_corrupt = "BAD_" + secrets.token_hex(12)
    rows = (
        ["0.1"] * pre_count
        + ["ERR", "NaN", random_corrupt]
        + ["1e16"]
        + ["0.1"] * post_count
        + ["not-a-number"]
    )

    finite_values = []
    naive_expected = 0.0
    corrupted_expected = 0
    for value in rows:
        try:
            parsed = float(value)
            if not math.isfinite(parsed):
                raise ValueError("non-finite value")
        except (TypeError, ValueError):
            parsed = 0.0
            corrupted_expected += 1
        finite_values.append(parsed)
        naive_expected += parsed
    precise_expected = math.fsum(finite_values)

    try:
        with open(data_path, "w", newline="") as f:
            for row in rows:
                f.write(row + "\n")
        if os.path.exists(result_path):
            os.remove(result_path)

        completed = subprocess.run(
            [sys.executable, aggregator_path],
            cwd=PIPELINE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
        assert completed.returncode == 0, "aggregator.py failed on fresh input:\n" + completed.stdout
        assert os.path.isfile(result_path), "aggregator.py did not create result.json when executed"

        with open(result_path, "r") as f:
            generated = json.load(f)

        assert "naive_sum" in generated, "naive_sum missing from generated result.json"
        assert "precise_sum" in generated, "precise_sum missing from generated result.json"
        assert "corrupted_count" in generated, "corrupted_count missing from generated result.json"
        assert generated["naive_sum"] == naive_expected, f"aggregator naive_sum incorrect: expected {naive_expected}, got {generated['naive_sum']}"
        assert generated["precise_sum"] == precise_expected, f"aggregator precise_sum incorrect: expected {precise_expected}, got {generated['precise_sum']}"
        assert generated["corrupted_count"] == corrupted_expected, f"aggregator corrupted_count incorrect: expected {corrupted_expected}, got {generated['corrupted_count']}"
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
        with open(result_path, "wb") as f:
            f.write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
