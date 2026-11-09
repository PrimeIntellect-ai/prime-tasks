#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/home/user/pipeline_manager/target/release/pipeline_manager"
PROJECT_DIR = "/home/user/pipeline_manager"
FOUR_DECIMALS = re.compile(r"^-?\d+\.\d{4}$")


@pytest.fixture(scope="session", autouse=True)
def build_project():
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Cargo.toml")), "Missing Cargo.toml"
    result = subprocess.run(
        ["cargo", "clean"], cwd=PROJECT_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    result = subprocess.run(
        ["cargo", "build", "--release"], cwd=PROJECT_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=360
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert os.path.isfile(BINARY_PATH), "Release binary was not produced"
    assert os.access(BINARY_PATH, os.X_OK), "Release artifact is not executable"


def run_tool(args):
    return subprocess.run(
        [BINARY_PATH] + args,
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )


def assert_validation(path, poisoned):
    result = run_tool(["validate", path])
    expected_code = 1 if poisoned else 0
    expected_text = "REJECT" if poisoned else "ACCEPT"
    assert result.returncode == expected_code, (
        f"validate returned {result.returncode}, expected {expected_code}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.decode(errors="replace").strip() == expected_text, (
        f"validate must print {expected_text}; got {result.stdout!r}"
    )


def test_validate_adversarial_corpus():
    evil_dir = "/app/evil_corpus"
    clean_dir = "/app/clean_corpus"
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")]
    assert evil_files and clean_files
    for path in evil_files:
        assert_validation(path, True)
    for path in clean_files:
        assert_validation(path, False)


def test_validate_generated_unseen_inputs():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="validation_") as directory:
        cases = []
        for i in range(30):
            poisoned = (i % 2 == 0)
            rows = []
            for j in range(rng.randint(3, 9)):
                mode = rng.randrange(3)
                if mode == 0:
                    amount = rng.uniform(50000.01, 150000.0)
                    age = rng.uniform(30.0, 90.0)
                elif mode == 1:
                    amount = rng.uniform(-1000.0, 50000.0)
                    age = rng.uniform(0.0, 29.999)
                else:
                    amount = rng.uniform(-1000.0, 49999.0)
                    age = rng.uniform(30.0, 90.0)
                rows.append([secrets.token_hex(6), rng.choice(["train", "test"]), f"{amount:.6f}", f"{age:.6f}"])

            # Exercise both strict boundaries explicitly.
            rows.append([secrets.token_hex(6), "test", "50000.000000", f"{rng.uniform(1, 29):.6f}"])
            rows.append([secrets.token_hex(6), "train", f"{rng.uniform(50001, 90000):.6f}", "30.000000"])
            if poisoned:
                pos = rng.randrange(len(rows) + 1)
                rows.insert(pos, [secrets.token_hex(6), rng.choice(["train", "test"]),
                                  f"{rng.uniform(50000.01, 200000):.6f}",
                                  f"{rng.uniform(0, 29.999):.6f}"])

            path = os.path.join(directory, f"case_{secrets.token_hex(10)}.csv")
            with open(path, "w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(["transaction_id", "split_type", "amount", "account_age"])
                writer.writerows(rows)
            cases.append((path, poisoned))

        rng.shuffle(cases)
        for path, poisoned in cases:
            assert_validation(path, poisoned)


def stats(values, sample):
    mean = sum(values) / len(values)
    divisor = len(values) - 1 if sample else len(values)
    variance = sum((x - mean) ** 2 for x in values) / divisor
    return mean, math.sqrt(variance)


def verify_engineered(input_path, output_path):
    with open(input_path, newline="") as handle:
        input_rows = list(csv.DictReader(handle))
    with open(output_path, newline="") as handle:
        raw_output = list(csv.reader(handle))

    expected_header = ["transaction_id", "split_type", "amount", "account_age"]
    assert raw_output, "Output CSV is empty"
    assert raw_output[0] == expected_header, "Output column order changed"
    assert all(len(row) == 4 for row in raw_output[1:]), "Output has missing or extra columns"

    with open(output_path, newline="") as handle:
        output_rows = list(csv.DictReader(handle))
    assert len(output_rows) == len(input_rows), "Output CSV row count mismatch"

    for original, output, raw in zip(input_rows, output_rows, raw_output[1:]):
        assert output["transaction_id"] == original["transaction_id"], "transaction_id was changed or reordered"
        assert output["split_type"] == original["split_type"], "split_type was changed or reordered"
        assert FOUR_DECIMALS.fullmatch(raw[2]), f"amount is not formatted to four decimals: {raw[2]!r}"
        assert FOUR_DECIMALS.fullmatch(raw[3]), f"account_age is not formatted to four decimals: {raw[3]!r}"

    train_amounts = [float(row["amount"]) for row in input_rows if row["split_type"] == "train"]
    train_ages = [float(row["account_age"]) for row in input_rows if row["split_type"] == "train"]
    assert len(train_amounts) >= 2

    # The instruction does not select population versus sample standard deviation.
    # Accept either convention, but require one convention to match every value.
    conventions = []
    for sample in (False, True):
        mean_amount, std_amount = stats(train_amounts, sample)
        mean_age, std_age = stats(train_ages, sample)
        expected = []
        for row in input_rows:
            expected.append((
                (float(row["amount"]) - mean_amount) / std_amount,
                (float(row["account_age"]) - mean_age) / std_age,
            ))
        conventions.append(expected)

    def matches(expected):
        for row, (expected_amount, expected_age) in zip(output_rows, expected):
            if not math.isclose(float(row["amount"]), expected_amount, rel_tol=0.0, abs_tol=0.000051):
                return False
            if not math.isclose(float(row["account_age"]), expected_age, rel_tol=0.0, abs_tol=0.000051):
                return False
        return True

    assert any(matches(expected) for expected in conventions), (
        "Scaled values do not consistently use train-only population or sample statistics"
    )


def run_and_verify_engineer(input_path):
    with tempfile.TemporaryDirectory(prefix="engineered_") as directory:
        output_path = os.path.join(directory, f"result_{secrets.token_hex(10)}.csv")
        result = run_tool(["engineer", input_path, output_path])
        assert result.returncode == 0, (
            f"engineer failed with {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(output_path), "engineer did not create the requested output file"
        verify_engineered(input_path, output_path)


def test_engineer_data_leakage():
    input_path = "/app/leak_test_input.csv"
    assert os.path.isfile(input_path), f"Missing input file: {input_path}"
    run_and_verify_engineer(input_path)


def test_engineer_generated_unseen_inputs():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="inputs_") as directory:
        for _ in range(7):
            train_count = rng.randint(4, 8)
            test_count = rng.randint(3, 7)
            rows = []
            for i in range(train_count):
                rows.append([
                    f"txn-{secrets.token_hex(7)}",
                    "train",
                    f"{rng.uniform(50.0, 5000.0) + i * 37.123:.6f}",
                    f"{rng.uniform(5.0, 70.0) + i * 0.731:.6f}",
                ])
            for i in range(test_count):
                # Deliberately different scale so full-dataset statistics cannot pass.
                rows.append([
                    f"txn-{secrets.token_hex(7)}",
                    "test",
                    f"{rng.uniform(50000.0, 300000.0) + i * 91.7:.6f}",
                    f"{rng.uniform(100.0, 600.0) + i * 1.19:.6f}",
                ])
            rng.shuffle(rows)
            input_path = os.path.join(directory, f"source_{secrets.token_hex(10)}.csv")
            with open(input_path, "w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(["transaction_id", "split_type", "amount", "account_age"])
                writer.writerows(rows)
            run_and_verify_engineer(input_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
