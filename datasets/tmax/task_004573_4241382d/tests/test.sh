#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import random
import re
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/run_pipeline.sh"
DATASET_PATH = "/home/user/research_data/dataset.csv"
PREDICTIONS_PATH = "/home/user/predictions.csv"

with open(DATASET_PATH, "rb") as f:
    ORIGINAL_DATASET = f.read()


@pytest.fixture(scope="session", autouse=True)
def restore_original_dataset():
    yield
    with open(DATASET_PATH, "wb") as f:
        f.write(ORIGINAL_DATASET)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable. Did you forget to run 'chmod +x'?"

    with open(SCRIPT_PATH, "rb") as f:
        raw = f.read()
    assert b"\x00" not in raw, "run_pipeline.sh must be a Bash text script."
    source = raw.decode("utf-8", errors="strict")
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(r"^#!.*\bbash\b", first_line), "run_pipeline.sh must use Bash."

    active_source = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert not re.search(r"(?i)(?<![A-Za-z0-9_])(python(?:[0-9.]*)?|rscript)(?![A-Za-z0-9_])", active_source), (
        "The pipeline must not invoke Python or R."
    )
    syntax = subprocess.run(["/bin/bash", "-n", SCRIPT_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid Bash syntax:\n{syntax.stderr}"


def expected_predictions(dataset_text):
    rows = list(csv.DictReader(io.StringIO(dataset_text)))
    training = [row for row in rows if row["split"] == "train"]

    frequencies = {}
    for row in training:
        for word in row["text"].lower().split():
            if len(word) >= 4:
                frequencies[word] = frequencies.get(word, 0) + 1

    features = [
        word for word, _ in sorted(frequencies.items(), key=lambda item: (-item[1], item[0]))[:10]
    ]
    feature_set = set(features)

    document_counts = {"A": 0, "B": 0}
    word_counts = {"A": {word: 0 for word in features}, "B": {word: 0 for word in features}}
    totals = {"A": 0, "B": 0}

    for row in training:
        label = row["label"]
        document_counts[label] += 1
        for word in row["text"].lower().split():
            if word in feature_set:
                word_counts[label][word] += 1
                totals[label] += 1

    training_count = len(training)
    output = ["id,prediction"]
    for row in rows:
        if row["split"] != "test":
            continue

        scores = {}
        words = row["text"].lower().split()
        for label in ("A", "B"):
            scores[label] = math.log(document_counts[label] / training_count)
            for word in words:
                if word in feature_set:
                    probability = (word_counts[label][word] + 1) / (totals[label] + 10)
                    scores[label] += math.log(probability)

        prediction = "A" if scores["A"] >= scores["B"] else "B"
        output.append(f'{row["id"]},{prediction}')

    return output


def run_pipeline_and_read_lines():
    if os.path.exists(PREDICTIONS_PATH):
        os.remove(PREDICTIONS_PATH)

    try:
        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (
            f"Script failed with return code {result.returncode}.\nStderr: {result.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The pipeline did not finish within 30 seconds.")

    assert os.path.isfile(PREDICTIONS_PATH), (
        f"The predictions file {PREDICTIONS_PATH} was not created by the script."
    )
    with open(PREDICTIONS_PATH, "r") as f:
        content = f.read().strip()
    return [line.strip() for line in content.split("\n") if line.strip()]


def write_dataset(rows):
    text = "id,split,label,text\n" + "\n".join(
        f"{row[0]},{row[1]},{row[2]},{row[3]}" for row in rows
    ) + "\n"
    with open(DATASET_PATH, "w", newline="") as f:
        f.write(text)
    return text


def token(prefix):
    return prefix + secrets.token_hex(5)


def fresh_ids(count):
    result = set()
    while len(result) < count:
        result.add(str(secrets.randbelow(800000) + 10000))
    return iter(result)


def test_predictions_correct_on_original_dataset():
    with open(DATASET_PATH, "wb") as f:
        f.write(ORIGINAL_DATASET)

    actual_lines = run_pipeline_and_read_lines()
    expected_lines = [
        "id,prediction",
        "101,A",
        "102,B",
        "103,A",
        "104,B",
    ]
    assert actual_lines == expected_lines, (
        f"The contents of {PREDICTIONS_PATH} do not match the expected predictions.\n"
        f"Expected: {expected_lines}\nGot: {actual_lines}"
    )


def test_training_only_features_on_unseen_dataset():
    # There are exactly ten training words. The high-frequency word appearing
    # only in test rows must not enter the feature vocabulary and displace key_b.
    p, q, common, key_a, fill_a = [token("wa") for _ in range(5)]
    r, s, key_b, fill_b, fill_c = [token("wb") for _ in range(5)]
    leak = token("leak")
    ids = fresh_ids(6)

    train_a = " ".join([p] * 6 + [q] * 3 + [common] * 4 + [key_a] * 2 + [fill_a] * 2)
    train_b = " ".join([r] * 6 + [s] * 3 + [common] * 4 + [key_b] + [fill_b] * 2 + [fill_c] * 2)
    leaked_text = " ".join([leak] * 30)

    tests = [
        (next(ids), "test", "?", f"{key_b} {leaked_text}"),
        (next(ids), "test", "?", f"{p} {q} {leaked_text}"),
        (next(ids), "test", "?", f"{r} {s} {leaked_text}"),
        (next(ids), "test", "?", f"{key_a} {p} {leaked_text}"),
    ]
    random.SystemRandom().shuffle(tests)
    rows = [
        (next(ids), "train", "A", train_a),
        (next(ids), "train", "B", train_b),
    ] + tests

    dataset_text = write_dataset(rows)
    expected_lines = expected_predictions(dataset_text)
    actual_lines = run_pipeline_and_read_lines()
    assert actual_lines == expected_lines, (
        "Predictions on a generated dataset were incorrect. Feature selection, training, "
        "and inference must be derived from the current dataset using training rows only.\n"
        f"Expected: {expected_lines}\nGot: {actual_lines}"
    )


def test_model_on_second_generated_dataset():
    x, y, z, shared, alpha, beta, fa, fb, fc, fd, extra, unseen = [
        token("term") for _ in range(12)
    ]
    ids = fresh_ids(8)
    rows = [
        (next(ids), "train", "A", f"{x} {x} {x} {shared} {alpha} {fa} tiny"),
        (next(ids), "train", "A", f"{x} {y} {shared} {alpha} {fb}"),
        (next(ids), "train", "A", f"{y} {y} {shared} {fc} {extra}"),
        (next(ids), "train", "B", f"{z} {z} {z} {z} {shared} {beta} {beta} {fd}"),
    ]
    tests = [
        (next(ids), "test", "?", f"{x} {alpha}"),
        (next(ids), "test", "?", f"{z} {beta} {beta}"),
        (next(ids), "test", "?", unseen),
        (next(ids), "test", "?", f"{y} {z} {shared}"),
    ]
    random.SystemRandom().shuffle(tests)
    dataset_text = write_dataset(rows + tests)

    expected_lines = expected_predictions(dataset_text)
    actual_lines = run_pipeline_and_read_lines()
    assert actual_lines == expected_lines, (
        "Predictions on a second generated dataset were incorrect.\n"
        f"Expected: {expected_lines}\nGot: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
