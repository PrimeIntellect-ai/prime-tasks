#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
from collections import Counter

import pytest

SOURCE = "/home/user/analyze.cpp"
TITLES = "/home/user/titles.txt"
RESULT = "/home/user/result.txt"
BINARY = "/tmp/analyze_submission"
ORIGINAL_TITLES = """data structures in c
advanced c programming structures computing
intro to machine learning
machine learning and data analysis
data analysis with c programming structures
"""
ORIGINAL_RESULT = "0 4 0.6124"


def test_analyze_cpp_exists():
    path = SOURCE
    assert os.path.isfile(path), f"File {path} is missing. The C++ source code must be created."


def test_result_txt_exists():
    path = RESULT
    assert os.path.isfile(path), f"File {path} is missing. The program must produce this output file."


def test_result_txt_content():
    path = RESULT
    if not os.path.isfile(path):
        pytest.fail(f"File {path} is missing.")

    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = ORIGINAL_RESULT
    assert content == expected_content, f"Content of {path} is incorrect. Expected '{expected_content}', but got '{content}'."


def expected_result(dataset):
    documents = []
    vocabulary = set()
    for line in dataset.splitlines():
        words = []
        for token in line.split():
            cleaned = "".join(ch.lower() for ch in token if ch.isalnum())
            if cleaned:
                words.append(cleaned)
                vocabulary.add(cleaned)
        documents.append(Counter(words))

    assert len(documents) >= 2
    vocabulary = sorted(vocabulary)
    vectors = []
    for counts in documents:
        vector = [counts[word] for word in vocabulary]
        norm = math.sqrt(sum(value * value for value in vector))
        if norm:
            vector = [value / norm for value in vector]
        else:
            vector = [0.0 for value in vector]
        vectors.append(vector)

    best_pair = None
    best_score = -1.0
    for i in range(len(vectors)):
        for j in range(i + 1, len(vectors)):
            score = sum(a * b for a, b in zip(vectors[i], vectors[j]))
            if score > best_score + 1e-12:
                best_score = score
                best_pair = (i, j)

    return f"{best_pair[0]} {best_pair[1]} {best_score:.4f}"


def run_case(dataset, expected=None):
    if expected is None:
        expected = expected_result(dataset)

    with open(TITLES, "w") as f:
        f.write(dataset)
    if os.path.exists(RESULT):
        os.remove(RESULT)

    completed = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"Program exited with status {completed.returncode}. stderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULT), "Running the compiled program did not create /home/user/result.txt."
    with open(RESULT, "r") as f:
        actual = f.read().strip()
    assert actual == expected, f"For dataset {dataset!r}, expected '{expected}', but got '{actual}'."


def make_random_case():
    rng = secrets.SystemRandom()
    words = ["w" + secrets.token_hex(5) for _ in range(10)]
    lines = []
    for document_index in range(8):
        tokens = []
        for word in words:
            count = secrets.randbelow(4)
            for _ in range(count):
                style = secrets.randbelow(4)
                if style == 0:
                    token = word.upper()
                elif style == 1:
                    token = "(" + word + "),"
                elif style == 2:
                    cut = 1 + secrets.randbelow(len(word) - 1)
                    token = word[:cut] + "-" + word[cut:]
                else:
                    token = word
                tokens.append(token)
        if not tokens:
            tokens.append(words[document_index % len(words)])
        rng.shuffle(tokens)
        lines.append(("\t" if document_index % 2 else " ").join(tokens))
    return "\n".join(lines) + "\n"


def test_source_compiles_and_program_computes_results():
    if os.path.exists(BINARY):
        os.remove(BINARY)
    compiled = subprocess.run(
        ["g++", "-std=c++17", "-O3", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f"analyze.cpp failed to compile: {compiled.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    crafted = """C++ data-driven DATA
c datadriven data
!!!
alpha alpha beta
alpha beta beta
"""
    run_case(crafted)
    run_case(make_random_case())

    # Re-run on the required dataset rather than trusting a pre-created result file.
    run_case(ORIGINAL_TITLES, ORIGINAL_RESULT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
