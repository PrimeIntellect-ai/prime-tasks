#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess

import pytest

SOURCE = "/home/user/src/pipeline.cpp"
BINARY = "/home/user/src/pipeline"
DATA = "/home/user/data/documents.csv"
LOG = "/home/user/output/experiment_log.json"
VOCAB = ["data", "science", "pipeline", "agent", "model"]


@pytest.fixture(scope="session")
def built_pipeline():
    assert os.path.isfile(SOURCE), f"Expected source file is missing: {SOURCE}"
    assert not os.path.islink(SOURCE), f"Source must be a regular file: {SOURCE}"

    with open(DATA, "rb") as f:
        original_data = f.read()

    result = subprocess.run(
        ["g++", "-std=c++11", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), \
        "Compilation did not produce an executable pipeline"

    try:
        yield original_data
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)


def expected_result(rows):
    embeddings = []
    integer_pattern = re.compile(r"[+-]?\d+")

    for row in rows:
        columns = row.split(",")
        if len(columns) != 3 or integer_pattern.fullmatch(columns[0]) is None:
            continue
        counts = [0] * len(VOCAB)
        for token in columns[1].split():
            if token in VOCAB:
                counts[VOCAB.index(token)] += 1
        embeddings.append(counts)

    total = 0.0
    pairs = 0
    for i in range(len(embeddings)):
        for j in range(i + 1, len(embeddings)):
            a, b = embeddings[i], embeddings[j]
            dot = sum(x * y for x, y in zip(a, b))
            norm_a = math.sqrt(sum(x * x for x in a))
            norm_b = math.sqrt(sum(x * x for x in b))
            total += 0.0 if norm_a == 0 or norm_b == 0 else dot / (norm_a * norm_b)
            pairs += 1

    average = total / pairs if pairs else 0.0
    return len(embeddings), float(f"{average:.4f}")


def run_case(rows):
    with open(DATA, "w", encoding="utf-8", newline="") as f:
        f.write("id,text,category\n")
        for row in rows:
            f.write(row + "\n")

    if os.path.lexists(LOG):
        os.remove(LOG)

    result = subprocess.run(
        [BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, \
        f"Pipeline exited with {result.returncode}:\n{result.stderr}"
    assert os.path.isfile(LOG), "Pipeline did not create experiment_log.json"

    with open(LOG, "r", encoding="utf-8") as f:
        raw = f.read()

    # Enforce the requested two-field JSON shape and four decimal places.
    pattern = re.compile(
        r'^\s*\{\s*"valid_rows"\s*:\s*(-?\d+)\s*,\s*'
        r'"avg_similarity"\s*:\s*(-?\d+\.\d{4})\s*\}\s*$'
    )
    assert pattern.fullmatch(raw), \
        "experiment_log.json is not in the required format with four decimal places"

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        pytest.fail(f"experiment_log.json is invalid JSON: {exc}")

    expected_rows, expected_similarity = expected_result(rows)
    assert data["valid_rows"] == expected_rows
    assert isinstance(data["valid_rows"], int)
    assert isinstance(data["avg_similarity"], (int, float))
    assert math.isclose(data["avg_similarity"], expected_similarity, abs_tol=1e-9)


def test_pipeline_is_compiled_and_executed_on_derived_cases(built_pipeline):
    targeted_rows = [
        "10,data science,x",
        "-2,data data,x",
        "+3,science model,x",
        "004,pipeline agent model,x",
        "bad,data,x",
        "5x,agent,x",
        "6,data,x,extra",
        "7,data",
        ",model,x",
        "8,,x",
    ]

    rng = random.SystemRandom()
    random_rows = []
    words = VOCAB + ["noise", "other"]
    for index in range(8):
        text = " ".join(rng.choice(words) for _ in range(rng.randint(1, 7)))
        random_rows.append(f"{rng.randint(1000, 999999)},{text},cat{index}")
    random_rows.extend([
        "not_an_integer,data model,bad",
        "12oops,pipeline agent,bad",
        "77,data science,bad,extra",
        "88,model",
    ])

    try:
        run_case(targeted_rows)
        run_case(random_rows)
    finally:
        # Restore the supplied dataset and regenerate the artifact checked by
        # the original verifier assertions below.
        with open(DATA, "wb") as f:
            f.write(built_pipeline)
        if os.path.lexists(LOG):
            os.remove(LOG)
        subprocess.run([BINARY], check=True, timeout=10)


def test_experiment_log_exists():
    log_path = "/home/user/output/experiment_log.json"
    assert os.path.isfile(log_path), f"Expected output file is missing: {log_path}"


def test_experiment_log_content():
    log_path = "/home/user/output/experiment_log.json"
    assert os.path.isfile(log_path), f"Expected output file is missing: {log_path}"

    with open(log_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {log_path} does not contain valid JSON.")

    assert "valid_rows" in data, "JSON is missing the 'valid_rows' key."
    assert "avg_similarity" in data, "JSON is missing the 'avg_similarity' key."

    assert isinstance(data["valid_rows"], int), "'valid_rows' must be an integer."
    assert data["valid_rows"] == 4, f"Expected 4 valid_rows, got {data['valid_rows']}."

    assert isinstance(data["avg_similarity"], (int, float)), "'avg_similarity' must be a number."
    expected_sim = 0.3841
    actual_sim = data["avg_similarity"]
    assert math.isclose(actual_sim, expected_sim, abs_tol=1e-4), \
        f"Expected avg_similarity to be approximately {expected_sim}, got {actual_sim}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
