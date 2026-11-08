#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess

import pytest

SOURCE = "/home/user/pipeline.cpp"
DATASET = "/home/user/transactions.csv"
CI_FILE = "/home/user/ci_results.csv"
MODEL_FILE = "/home/user/model_results.txt"
EXECUTABLE = "/tmp/pipeline_submission"


def run_pipeline():
    for path in (CI_FILE, MODEL_FILE):
        if os.path.exists(path):
            os.remove(path)
    subprocess.run([EXECUTABLE], cwd="/home/user", check=True, timeout=20)


@pytest.fixture(scope="session", autouse=True)
def compiled_pipeline():
    assert os.path.isfile(SOURCE), f"Expected C++ source file {SOURCE} is missing."
    assert os.path.getsize(SOURCE) > 0, f"Expected C++ source file {SOURCE} is empty."

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    # Tokenization and has_good do not affect either requested statistical output,
    # so verify that the submitted implementation contains the requested feature logic.
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    code = re.sub(r"//[^\n]*", "", code)
    assert re.search(r"has_?good", code, re.IGNORECASE), "Missing implementation of the has_good feature."
    assert re.search(r"\btolower\s*\(", code), "Missing case-insensitive token handling (tolower)."
    assert re.search(r"\b(?:ispunct|isalnum)\s*\(", code), "Missing punctuation stripping logic."
    assert re.search(r"(?:istringstream|stringstream|\bisspace\s*\(|\\s)", code), "Missing whitespace tokenization logic."
    assert re.search(r'[\"\']good[\"\']', code, re.IGNORECASE), "Missing comparison with the token good."

    build = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", EXECUTABLE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert build.returncode == 0, f"pipeline.cpp did not compile:\n{build.stderr}"

    with open(DATASET, "rb") as f:
        original_dataset = f.read()

    run_pipeline()
    yield

    # Leave the requested outputs corresponding to the original supplied dataset.
    with open(DATASET, "wb") as f:
        f.write(original_dataset)
    try:
        run_pipeline()
    except Exception:
        pass


def test_ci_results_file():
    ci_file = "/home/user/ci_results.csv"
    assert os.path.isfile(ci_file), f"Expected output file {ci_file} is missing."

    with open(ci_file, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 3, f"Expected exactly 3 rows in {ci_file} (1 header + 2 data rows), found {len(rows)}."

    header = rows[0]
    assert header == ["group", "mean", "lower_bound", "upper_bound"], f"Incorrect header in {ci_file}: {header}"

    data_rows = rows[1:]
    results = {row[0]: row[1:] for row in data_rows if len(row) == 4}

    assert "Positive" in results, "Missing 'Positive' group in ci_results.csv"
    assert "Negative" in results, "Missing 'Negative' group in ci_results.csv"

    pos_mean, pos_lower, pos_upper = results["Positive"]
    assert pos_mean == "174.100", f"Expected Positive mean to be '174.100', got {pos_mean}"
    assert pos_lower == "104.189", f"Expected Positive lower_bound to be '104.189', got {pos_lower}"
    assert pos_upper == "244.011", f"Expected Positive upper_bound to be '244.011', got {pos_upper}"

    neg_mean, neg_lower, neg_upper = results["Negative"]
    assert neg_mean == "65.000", f"Expected Negative mean to be '65.000', got {neg_mean}"
    assert neg_lower == "48.026", f"Expected Negative lower_bound to be '48.026', got {neg_lower}"
    assert neg_upper == "81.974", f"Expected Negative upper_bound to be '81.974', got {neg_upper}"


def test_model_results_file():
    model_file = "/home/user/model_results.txt"
    assert os.path.isfile(model_file), f"Expected output file {model_file} is missing."

    with open(model_file, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) >= 2, f"Expected at least 2 lines in {model_file}, found {len(content)}."

    slope_line = None
    intercept_line = None
    for line in content:
        if line.startswith("Slope:"):
            slope_line = line
        elif line.startswith("Intercept:"):
            intercept_line = line

    assert slope_line is not None, "Missing 'Slope:' line in model_results.txt"
    assert intercept_line is not None, "Missing 'Intercept:' line in model_results.txt"

    slope_val = slope_line.split(":")[1].strip()
    intercept_val = intercept_line.split(":")[1].strip()

    assert slope_val == "0.016", f"Expected Slope to be '0.016', got '{slope_val}'"
    assert intercept_val == "1.443", f"Expected Intercept to be '1.443', got '{intercept_val}'"


def expected_values(records):
    groups = {
        "Positive": [r[2] for r in records if r[4] >= 4],
        "Negative": [r[2] for r in records if r[4] < 4],
    }
    ci = {}
    for name, values in groups.items():
        mean = sum(values) / len(values)
        variance = sum((x - mean) ** 2 for x in values) / (len(values) - 1)
        margin = 1.96 * math.sqrt(variance) / math.sqrt(len(values))
        ci[name] = (f"{mean:.3f}", f"{mean - margin:.3f}", f"{mean + margin:.3f}")

    xs = [r[2] for r in records]
    ys = [r[4] for r in records]
    x_mean = sum(xs) / len(xs)
    y_mean = sum(ys) / len(ys)
    slope = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys)) / sum((x - x_mean) ** 2 for x in xs)
    intercept = y_mean - slope * x_mean
    return ci, f"{slope:.3f}", f"{intercept:.3f}"


def test_pipeline_recomputes_from_dataset():
    rng = random.SystemRandom()
    shift = rng.randint(17, 83)
    amounts = [31, 57, 84, 116, 149, 193, 238, 276, 325, 371, 418, 467]
    ratings = [1, 5, 2, 4, 3, 5, 1, 4, 2, 5, 3, 4]
    reviews = [
        "GOOD! value",
        "ordinary item",
        "This is good, indeed.",
        "not-good wording",
        "Really\tGood? yes",
        "bad experience",
        "(good) packaging",
        "Nothing special",
        "GoOd!!!",
        "fine, but average",
        "good; useful",
        "excellent purchase",
    ]
    records = [
        (i + 101, 20 + (i * 3) % 47, float(amount + shift), reviews[i], ratings[i])
        for i, amount in enumerate(amounts)
    ]

    with open(DATASET, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["transaction_id", "age", "purchase_amount", "review_text", "rating"])
        for record in records:
            writer.writerow(record)

    run_pipeline()
    expected_ci, expected_slope, expected_intercept = expected_values(records)

    assert os.path.isfile(CI_FILE), f"Expected output file {CI_FILE} is missing after execution."
    with open(CI_FILE, newline="") as f:
        rows = list(csv.reader(f))
    assert len(rows) == 3, f"Expected exactly 3 rows in {CI_FILE}, found {len(rows)}."
    assert rows[0] == ["group", "mean", "lower_bound", "upper_bound"], f"Incorrect header in {CI_FILE}: {rows[0]}"
    results = {row[0]: tuple(row[1:]) for row in rows[1:] if len(row) == 4}
    assert results.get("Positive") == expected_ci["Positive"], f"Incorrect recomputed Positive CI: {results.get('Positive')}"
    assert results.get("Negative") == expected_ci["Negative"], f"Incorrect recomputed Negative CI: {results.get('Negative')}"

    assert os.path.isfile(MODEL_FILE), f"Expected output file {MODEL_FILE} is missing after execution."
    with open(MODEL_FILE) as f:
        lines = f.read().strip().splitlines()
    slope_lines = [line for line in lines if line.startswith("Slope:")]
    intercept_lines = [line for line in lines if line.startswith("Intercept:")]
    assert slope_lines, "Missing 'Slope:' line after execution."
    assert intercept_lines, "Missing 'Intercept:' line after execution."
    assert slope_lines[-1].split(":", 1)[1].strip() == expected_slope, "Incorrect recomputed regression slope."
    assert intercept_lines[-1].split(":", 1)[1].strip() == expected_intercept, "Incorrect recomputed regression intercept."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
