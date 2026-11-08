#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import struct
import subprocess

import pytest

QUERY_PATH = "/home/user/query.bin"
EMBEDDINGS_PATH = "/home/user/embeddings.bin"
EXECUTABLE_PATH = "/home/user/sim_search"
DIM = 128


def load_vectors(query_path=QUERY_PATH, embeddings_path=EMBEDDINGS_PATH):
    if not os.path.exists(query_path) or not os.path.exists(embeddings_path):
        return None, None

    with open(query_path, "rb") as f:
        q_data = f.read()
    if len(q_data) != DIM * 4:
        return None, None

    with open(embeddings_path, "rb") as f:
        e_data = f.read()
    if not e_data or len(e_data) % (DIM * 4) != 0:
        return None, None

    query = struct.unpack(f"{DIM}f", q_data)
    num_embeddings = len(e_data) // (DIM * 4)
    embeddings = [
        struct.unpack(f"{DIM}f", e_data[i * DIM * 4:(i + 1) * DIM * 4])
        for i in range(num_embeddings)
    ]
    return query, embeddings


def compute_scores(query, embeddings):
    norm_q = math.sqrt(sum(q * q for q in query))
    scores = []
    for emb in embeddings:
        dot = sum(q * e for q, e in zip(query, emb))
        norm_e = math.sqrt(sum(e * e for e in emb))
        denom = norm_q * norm_e
        scores.append(dot / denom if denom != 0 else 0.0)
    return scores


def compute_expected_top5():
    query, embeddings = load_vectors()
    if query is None:
        return []
    scores = compute_scores(query, embeddings)
    return [str(i) for i in sorted(range(len(scores)), key=lambda i: scores[i], reverse=True)[:5]]


def run_and_check(query, embeddings):
    completed = subprocess.run(
        [EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert completed.returncode == 0, (
        f"sim_search exited with status {completed.returncode}: {completed.stderr}"
    )

    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    assert len(lines) == len(embeddings), (
        f"Expected {len(embeddings)} output lines, got {len(lines)}"
    )

    expected_scores = compute_scores(query, embeddings)
    for expected_index, (line, expected_score) in enumerate(zip(lines, expected_scores)):
        fields = line.split()
        assert len(fields) == 2, f"Malformed output line: {line!r}"
        try:
            actual_index = int(fields[0])
            actual_score = float(fields[1])
        except ValueError as exc:
            pytest.fail(f"Malformed output line {line!r}: {exc}")
        assert actual_index == expected_index, (
            f"Expected index {expected_index}, got {actual_index}"
        )
        assert math.isfinite(actual_score), f"Non-finite score for index {actual_index}"
        assert actual_score == pytest.approx(expected_score, abs=3e-5), (
            f"Incorrect similarity for index {actual_index}: "
            f"expected {expected_score}, got {actual_score}"
        )


def test_sim_search_c_fixed():
    path = "/home/user/sim_search.c"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "int dot = 0;" not in content, "The bug 'int dot = 0;' is still present in sim_search.c"
    assert "float dot" in content or "double dot" in content, "The dot product variable should be declared as a float or double."


def test_sim_search_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable missing: {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File is not executable: {EXECUTABLE_PATH}"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sim_search must be a compiled ELF executable"


def test_sim_search_executes_correctly_on_provided_data():
    query, embeddings = load_vectors()
    assert query is not None, "Missing or invalid binary input files"
    run_and_check(query, embeddings)


def test_sim_search_executes_correctly_on_independent_data():
    rng = random.Random(8675309)
    embeddings = [tuple(rng.uniform(-3.0, 3.0) for _ in range(DIM)) for _ in range(19)]
    query = tuple(embeddings[7][j] + rng.uniform(-0.05, 0.05) for j in range(DIM))

    with open(QUERY_PATH, "rb") as f:
        original_query = f.read()
    with open(EMBEDDINGS_PATH, "rb") as f:
        original_embeddings = f.read()

    try:
        with open(QUERY_PATH, "wb") as f:
            f.write(struct.pack(f"{DIM}f", *query))
        with open(EMBEDDINGS_PATH, "wb") as f:
            for emb in embeddings:
                f.write(struct.pack(f"{DIM}f", *emb))
        loaded_query, loaded_embeddings = load_vectors()
        run_and_check(loaded_query, loaded_embeddings)
    finally:
        with open(QUERY_PATH, "wb") as f:
            f.write(original_query)
        with open(EMBEDDINGS_PATH, "wb") as f:
            f.write(original_embeddings)


def test_top5_txt_correct():
    path = "/home/user/top5.txt"
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_top5 = compute_expected_top5()
    assert expected_top5, "Could not compute expected top 5 (missing or invalid binary files)."
    assert len(lines) == 5, f"Expected exactly 5 lines in top5.txt, got {len(lines)}"

    for i, (actual, expected) in enumerate(zip(lines, expected_top5)):
        assert actual == expected, f"Mismatch at rank {i+1}: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
