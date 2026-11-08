#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import subprocess
from collections import Counter

import pytest

TRAIN = "/home/user/train.tsv"
TEST = "/home/user/test.txt"
PRED = "/home/user/predictions.txt"
SOURCE = "/home/user/classifier.cpp"
EXECUTABLE = "/home/user/classifier"
REBUILT = "/tmp/classifier_from_source"


def run_program(path):
    if os.path.exists(PRED):
        os.remove(PRED)
    subprocess.run([path], cwd="/home/user", check=True, timeout=10)
    assert os.path.exists(PRED), f"{path} did not create {PRED}."
    with open(PRED, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def tokenize(text):
    normalized = re.sub(r"[^A-Za-z0-9]", " ", text.lower())
    return normalized.split()


def expected_predictions(training, tests):
    doc_counts = {0: 0, 1: 0}
    word_counts = {0: Counter(), 1: Counter()}
    totals = {0: 0, 1: 0}
    vocab = set()

    for label, text in training:
        doc_counts[label] += 1
        tokens = tokenize(text)
        word_counts[label].update(tokens)
        totals[label] += len(tokens)
        vocab.update(tokens)

    total_docs = len(training)
    vocab_size = len(vocab)
    answers = []
    for text in tests:
        tokens = tokenize(text)
        scores = {}
        for label in (0, 1):
            scores[label] = math.log(doc_counts[label] / total_docs)
            denominator = totals[label] + vocab_size
            for token in tokens:
                if token in vocab:
                    scores[label] += math.log((word_counts[label][token] + 1) / denominator)
        answers.append("1" if scores[1] >= scores[0] else "0")
    return answers


def write_dataset(training, tests):
    with open(TRAIN, "w", encoding="utf-8") as f:
        for label, text in training:
            f.write(f"{label}\t{text}\n")
    with open(TEST, "w", encoding="utf-8") as f:
        for text in tests:
            f.write(text + "\n")


def test_cpp_file_exists():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} does not exist."


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Compiled executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXECUTABLE} is not a compiled executable."


def test_predictions_txt_content():
    lines = run_program(EXECUTABLE)
    lines = [line.strip() for line in lines if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in predictions.txt, found {len(lines)}."
    assert lines[0] == "1", f"Expected first prediction to be '1', got '{lines[0]}'."
    assert lines[1] == "0", f"Expected second prediction to be '0', got '{lines[1]}'."


def test_classifier_on_derived_cases():
    subprocess.run(
        ["g++", "-O3", SOURCE, "-o", REBUILT],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    saved = {}
    for path in (TRAIN, TEST, PRED):
        saved[path] = open(path, "rb").read() if os.path.exists(path) else None

    rng = random.SystemRandom()
    try:
        for _ in range(4):
            words = ["w" + secrets.token_hex(6) for _ in range(7)]
            a, b, c, d, common, extra, unknown = words
            favored = rng.choice((0, 1))
            training = [
                (0, f"{a} {a} {common}"),
                (0, f"{a.upper()}--{c} {common}"),
                (1, f"{b} {b} {common}"),
                (1, f"{b.upper()},,{d} {common}"),
                (favored, f"{extra} {extra} {extra}"),
            ]
            tests = [
                f"{a.upper()}!!!{a}",
                f"{b},{b.upper()}",
                c,
                d,
                unknown,
                f"{common} {extra}",
                f"{a} {b} {unknown}",
                f"123-{a}-123",
            ]
            rng.shuffle(training)
            rng.shuffle(tests)
            expected = expected_predictions(training, tests)
            assert "0" in expected and "1" in expected
            write_dataset(training, tests)

            for program in (EXECUTABLE, REBUILT):
                actual = run_program(program)
                assert actual == expected, (
                    f"{program} produced {actual}, expected {expected} for a generated dataset."
                )
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
