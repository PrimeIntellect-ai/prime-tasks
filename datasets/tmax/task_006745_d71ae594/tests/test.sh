#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

HOME = "/home/user"
PROGRAM = os.path.join(HOME, "organizer.go")
LOG = os.path.join(HOME, "experiment_log.json")
BEST = os.path.join(HOME, "best_model.txt")
DATASET = os.path.join(HOME, "dataset")


def compute_expected(dataset_path):
    def embeddings(directory, dimension):
        result = []
        for name in sorted(os.listdir(directory)):
            path = os.path.join(directory, name)
            if not name.endswith(".txt") or not os.path.isfile(path):
                continue
            with open(path, "r", encoding="utf-8") as f:
                text = f.read().lower()
            counts = [0.0] * dimension
            for ch in text:
                index = ord(ch) - ord("a")
                if 0 <= index < dimension:
                    counts[index] += 1.0
            result.append(counts)
        return result

    errors = {}
    for dimension in range(1, 27):
        train = embeddings(os.path.join(dataset_path, "train"), dimension)
        val = embeddings(os.path.join(dataset_path, "val"), dimension)
        assert train, "Training set contains no .txt files."
        total = 0.0
        for val_vector in val:
            nearest = min(
                math.sqrt(sum((a - b) ** 2 for a, b in zip(val_vector, train_vector)))
                for train_vector in train
            )
            total += nearest
        errors[dimension] = math.floor(total * 100.0 + 0.5) / 100.0
    return errors


def run_program():
    assert os.path.isfile(PROGRAM), f"File {PROGRAM} is missing."
    assert not os.path.islink(PROGRAM), f"{PROGRAM} must be a Go source file, not a symlink."
    for path in (LOG, BEST):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    completed = subprocess.run(
        ["go", "run", PROGRAM],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f"Running {PROGRAM} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def load_and_validate(expected):
    assert os.path.isfile(LOG), f"File {LOG} is missing."
    with open(LOG, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{LOG} does not contain valid JSON: {exc}")

    assert isinstance(data, list), f"{LOG} should contain a JSON array."
    assert len(data) == 26, f"Expected 26 entries in {LOG}, got {len(data)}."

    by_dimension = {}
    for item in data:
        assert isinstance(item, dict), f"Each log entry must be an object, got {item!r}."
        assert "D" in item, f"Missing 'D' key in {item}"
        assert "error" in item, f"Missing 'error' key in {item}"
        dimension = item["D"]
        error = item["error"]
        assert isinstance(dimension, int) and not isinstance(dimension, bool), f"Invalid D in {item}"
        assert 1 <= dimension <= 26, f"D is out of range in {item}"
        assert dimension not in by_dimension, f"Duplicate entry for D={dimension}."
        assert isinstance(error, (int, float)) and not isinstance(error, bool), f"Invalid error in {item}"
        assert math.isfinite(float(error)), f"Non-finite error in {item}"
        by_dimension[dimension] = float(error)

    assert set(by_dimension) == set(range(1, 27)), "Log must contain every D from 1 through 26 exactly once."
    for dimension in range(1, 27):
        assert abs(by_dimension[dimension] - expected[dimension]) < 1e-9, (
            f"Expected error for D={dimension} to be {expected[dimension]:.2f}, "
            f"got {by_dimension[dimension]}."
        )

    assert os.path.isfile(BEST), f"File {BEST} is missing."
    with open(BEST, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected_best = min(expected, key=lambda d: (expected[d], d))
    assert content == str(expected_best), (
        f"Expected {BEST} to contain '{expected_best}', got '{content}'."
    )
    return by_dimension, content


@pytest.fixture(scope="module", autouse=True)
def execute_submission():
    run_program()


def test_experiment_log_exists_and_valid():
    expected = compute_expected(DATASET)
    load_and_validate(expected)


def test_experiment_log_specific_values():
    expected = compute_expected(DATASET)
    values, _ = load_and_validate(expected)
    assert values[1] == 1.00, f"Expected error for D=1 to be 1.00, got {values[1]}."
    assert values[3] == 2.00, f"Expected error for D=3 to be 2.00, got {values[3]}."


def test_best_model_txt():
    expected = compute_expected(DATASET)
    _, content = load_and_validate(expected)
    assert content == "1", f"Expected best_model.txt to contain '1', got '{content}'."


def test_program_on_unseen_dataset():
    backup = tempfile.mkdtemp(prefix="dataset-backup-")
    os.rmdir(backup)
    os.rename(DATASET, backup)
    try:
        os.makedirs(os.path.join(DATASET, "train"))
        os.makedirs(os.path.join(DATASET, "val"))
        alphabet = "abcdefghijklmnopqrstuvwxyz"

        def random_text(length):
            raw = secrets.token_bytes(length)
            chars = [alphabet[b % 26] for b in raw]
            for i in range(0, len(chars), 11):
                chars[i] = chars[i].upper()
            return "".join(chars) + " 1234!?"

        for i, length in enumerate((37, 49, 61, 73, 89)):
            with open(os.path.join(DATASET, "train", f"hidden_train_{i}.txt"), "w", encoding="utf-8") as f:
                f.write(random_text(length))
        for i, length in enumerate((41, 57, 79, 97)):
            with open(os.path.join(DATASET, "val", f"hidden_val_{i}.txt"), "w", encoding="utf-8") as f:
                f.write(random_text(length))

        expected = compute_expected(DATASET)
        run_program()
        load_and_validate(expected)
    finally:
        if os.path.exists(DATASET):
            shutil.rmtree(DATASET)
        os.rename(backup, DATASET)
        run_program()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
