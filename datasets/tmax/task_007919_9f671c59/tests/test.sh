#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import shutil
import subprocess

import pytest

HOME = "/home/user"
RESULTS_PATH = os.path.join(HOME, "results.json")
CORPUS_PATH = os.path.join(HOME, "corpus.txt")
VECTORS_PATH = os.path.join(HOME, "word_vectors.csv")
EXCLUDED = {RESULTS_PATH, CORPUS_PATH, VECTORS_PATH}


def load_results():
    assert os.path.isfile(RESULTS_PATH), f"Expected results file {RESULTS_PATH} does not exist."
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")


def candidate_commands():
    commands = []
    interpreters = {
        ".py": ["python3"],
        ".sh": ["bash"],
        ".pl": ["perl"],
        ".rb": ["ruby"],
        ".js": ["node"],
        ".php": ["php"],
    }

    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d != "__pycache__" and not d.startswith(".")]
        for name in files:
            path = os.path.abspath(os.path.join(root, name))
            if path in EXCLUDED or name.startswith("."):
                continue

            ext = os.path.splitext(name)[1].lower()
            if ext in interpreters and shutil.which(interpreters[ext][0]):
                commands.append(interpreters[ext] + [path])
                continue

            if os.access(path, os.X_OK):
                commands.append([path])
                continue

            try:
                with open(path, "rb") as f:
                    first_line = f.readline(256).decode("utf-8", "ignore")
            except OSError:
                continue
            if first_line.startswith("#!"):
                if "python" in first_line and shutil.which("python3"):
                    commands.append(["python3", path])
                elif ("bash" in first_line or "sh" in first_line) and shutil.which("bash"):
                    commands.append(["bash", path])

    return commands


def run_artifact(command):
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    completed = subprocess.run(
        command,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    if completed.returncode != 0 or not os.path.isfile(RESULTS_PATH):
        return None
    try:
        with open(RESULTS_PATH, "r") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def numeric_benchmark(results):
    value = results.get("benchmark_time_seconds") if isinstance(results, dict) else None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    if not math.isfinite(value) or value <= 0:
        return None
    return value


def test_script_executes_and_benchmark_is_measured():
    with open(CORPUS_PATH, "rb") as f:
        original_corpus = f.read()
    with open(VECTORS_PATH, "rb") as f:
        original_vectors = f.read()

    commands = candidate_commands()
    assert commands, "No runnable submission script was found under /home/user."

    selected = None
    errors = []
    for command in commands:
        try:
            with open(CORPUS_PATH, "wb") as f:
                f.write(original_corpus)
            with open(VECTORS_PATH, "wb") as f:
                f.write(original_vectors)
            result = run_artifact(command)
            if result is not None and numeric_benchmark(result) is not None:
                selected = command
                break
            errors.append(" ".join(command))
        except (OSError, subprocess.SubprocessError) as exc:
            errors.append(f"{' '.join(command)}: {exc}")

    assert selected is not None, "No submission script successfully generated results.json. Tried: " + "; ".join(errors)

    try:
        # A real timing of embedding the entire corpus must increase when the
        # corpus workload is quadrupled. This rejects a merely hardcoded
        # positive benchmark value while exercising the submitted artifact.
        with open(CORPUS_PATH, "wb") as f:
            f.write(original_corpus * 4)
        scaled_results = run_artifact(selected)
        scaled_time = numeric_benchmark(scaled_results)
        assert scaled_time is not None, "The script did not produce a valid benchmark for the scaled corpus."
    finally:
        with open(CORPUS_PATH, "wb") as f:
            f.write(original_corpus)
        with open(VECTORS_PATH, "wb") as f:
            f.write(original_vectors)

    final_results = run_artifact(selected)
    original_time = numeric_benchmark(final_results)
    assert original_time is not None, "The script did not regenerate a valid benchmark for the original corpus."
    assert scaled_time > original_time * 1.25, (
        "benchmark_time_seconds does not reflect measured whole-corpus work: "
        f"original={original_time}, four-times corpus={scaled_time}."
    )


def reference_values():
    vectors = {}
    with open(VECTORS_PATH, newline="") as f:
        for row in csv.reader(f):
            if not row:
                continue
            vectors[row[0].lower()] = [float(x) for x in row[1:]]

    dimension = 5

    def embed(text):
        tokens = re.findall(r"[a-z]+", text.lower())
        if not tokens:
            return [0.0] * dimension
        total = [0.0] * dimension
        for token in tokens:
            vector = vectors.get(token, [0.0] * dimension)
            for i in range(dimension):
                total[i] += vector[i]
        return [value / len(tokens) for value in total]

    def cosine(a, b):
        norm_a = math.sqrt(sum(x * x for x in a))
        norm_b = math.sqrt(sum(x * x for x in b))
        if norm_a == 0.0 or norm_b == 0.0:
            return 0.0
        return sum(x * y for x, y in zip(a, b)) / (norm_a * norm_b)

    query_vector = embed("machine learning accelerates data analysis")
    with open(CORPUS_PATH, "r") as f:
        corpus_vectors = [embed(line.rstrip("\n")) for line in f]
    similarities = [cosine(query_vector, vector) for vector in corpus_vectors]
    top_indices = sorted(range(len(similarities)), key=lambda i: (-similarities[i], i))[:3]
    return [round(x, 4) for x in query_vector], top_indices


def test_results_file_exists():
    assert os.path.isfile(RESULTS_PATH), f"Expected results file {RESULTS_PATH} does not exist."


def test_results_format_and_values():
    results = load_results()

    assert "query_vector" in results, "'query_vector' missing from results.json"
    assert "top_3_indices" in results, "'top_3_indices' missing from results.json"
    assert "benchmark_time_seconds" in results, "'benchmark_time_seconds' missing from results.json"

    expected_query_vector, expected_indices = reference_values()
    actual_query_vector = results["query_vector"]
    assert isinstance(actual_query_vector, list), "'query_vector' must be a list."
    assert len(actual_query_vector) == 5, "'query_vector' must have 5 elements."

    for expected, actual in zip(expected_query_vector, actual_query_vector):
        assert abs(expected - actual) < 1e-4, (
            f"query_vector values incorrect. Expected {expected_query_vector}, got {actual_query_vector}."
        )

    actual_indices = results["top_3_indices"]
    assert actual_indices == expected_indices, (
        f"top_3_indices incorrect. Expected {expected_indices}, got {actual_indices}."
    )

    benchmark_time = results["benchmark_time_seconds"]
    assert isinstance(benchmark_time, (float, int)), "'benchmark_time_seconds' must be a number."
    assert benchmark_time > 0, "'benchmark_time_seconds' must be greater than 0."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
