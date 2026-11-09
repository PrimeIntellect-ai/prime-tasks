#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import re
import subprocess
from collections import Counter

SCRIPT_PATH = "/home/user/prepare_data.sh"
RAW_PATH = "/home/user/raw_data.csv"
CSV_PATH = "/home/user/train_clean.csv"
EVALUATOR_PATH = "/app/model_evaluator"


def parse_csv_bytes(data):
    text = data.decode("utf-8-sig")
    return list(csv.reader(io.StringIO(text, newline="")))


def expected_selection(raw_bytes):
    records = parse_csv_bytes(raw_bytes)
    assert records, "raw_data.csv is empty."
    header = records[0]
    assert header == [f"f{i}" for i in range(1, 11)] + ["target"], \
        f"Unexpected raw_data.csv header: {header}"

    clean = []
    for line_number, row in enumerate(records[1:], 2):
        assert len(row) == 11, f"Raw row {line_number} has {len(row)} columns instead of 11."
        if any("?" in value for value in row):
            continue
        clean.append(row)

    assert clean, "No clean source rows are available."
    ys = [float(row[10]) for row in clean]
    y_mean = sum(ys) / len(ys)
    correlations = []

    for column in range(10):
        xs = [float(row[column]) for row in clean]
        x_mean = sum(xs) / len(xs)
        numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys))
        x_ss = sum((x - x_mean) ** 2 for x in xs)
        y_ss = sum((y - y_mean) ** 2 for y in ys)
        correlation = 0.0 if x_ss == 0 or y_ss == 0 else numerator / math.sqrt(x_ss * y_ss)
        correlations.append(correlation)

    ranked = sorted(range(10), key=lambda i: (-abs(correlations[i]), i))
    selected = {header[i] for i in ranked[:5]}
    return header, clean, selected


def validate_generated_csv(raw_bytes):
    source_header, clean_rows, selected = expected_selection(raw_bytes)

    assert os.path.isfile(CSV_PATH), f"Output dataset missing: {CSV_PATH} was not generated."
    with open(CSV_PATH, "r", encoding="utf-8-sig", newline="") as output_file:
        output_records = list(csv.reader(output_file))

    assert output_records, f"{CSV_PATH} is empty."
    output_header = output_records[0]
    assert len(output_header) == 6, \
        f"Output header must contain exactly 5 features and target, got: {output_header}"
    assert output_header[-1] == "target", \
        f"The target column must be last, got header: {output_header}"
    assert len(set(output_header)) == 6, f"Output header contains duplicate columns: {output_header}"
    assert set(output_header[:-1]) == selected, \
        f"Selected features are incorrect. Expected {sorted(selected)}, got {output_header[:-1]}"

    output_rows = output_records[1:]
    for line_number, row in enumerate(output_rows, 2):
        assert len(row) == 6, f"Output row {line_number} has {len(row)} columns instead of 6."
        assert not any("?" in value for value in row), \
            f"Output row {line_number} still contains missing-data marker '?'."

    source_indices = [source_header.index(name) for name in output_header]

    def numeric_tuple(row, context):
        try:
            values = tuple(float(value) for value in row)
        except ValueError as exc:
            raise AssertionError(f"{context} contains a non-numeric value: {row}") from exc
        assert all(math.isfinite(value) for value in values), f"{context} contains a non-finite value: {row}"
        return values

    expected_rows = Counter(
        numeric_tuple([row[index] for index in source_indices], "Source row")
        for row in clean_rows
    )
    actual_rows = Counter(
        numeric_tuple(row, f"Output row {line_number}")
        for line_number, row in enumerate(output_rows, 2)
    )
    assert actual_rows == expected_rows, \
        "train_clean.csv must contain exactly the cleaned rows projected from raw_data.csv; rows were added, omitted, altered, or not sourced from the input."

    return selected


def run_script():
    result = subprocess.run(["bash", SCRIPT_PATH], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, \
        f"Script {SCRIPT_PATH} failed to execute.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def make_variant(original_bytes):
    records = parse_csv_bytes(original_bytes)
    header, rows = records[0], records[1:]
    variant = [header]
    for i, row in enumerate(rows):
        changed = list(row)
        target = int(changed[10])
        changed[1] = f"{10.0 * target + ((i % 17) - 8) * 0.001:.4f}"  # f2: strong positive correlation
        changed[9] = f"{-8.0 * target + ((i % 19) - 9) * 0.001:.4f}" # f10: strong negative correlation
        changed[6] = f"{(((i * 37) % 101) - 50) / 10.0:.4f}"          # f7: deterministic noise
        if i == 0:
            changed[4] = "?"                                         # explicit row-cleaning check
        variant.append(changed)

    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerows(variant)
    return buffer.getvalue().encode("utf-8")


def test_complete_preprocessing_pipeline_and_accuracy():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH} must exist."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a real script, not a symbolic link."

    with open(RAW_PATH, "rb") as raw_file:
        original_raw = raw_file.read()

    run_script()
    with open(RAW_PATH, "rb") as raw_file:
        assert raw_file.read() == original_raw, "prepare_data.sh must not modify raw_data.csv."
    original_selected = validate_generated_csv(original_raw)

    assert os.path.isfile(EVALUATOR_PATH), f"Model evaluator missing: {EVALUATOR_PATH}"
    assert os.access(EVALUATOR_PATH, os.X_OK), f"Model evaluator {EVALUATOR_PATH} is not executable."
    result = subprocess.run([EVALUATOR_PATH, CSV_PATH], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, \
        f"Model evaluator failed to run on {CSV_PATH}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    match = re.search(r"ACCURACY=([0-9.]+)", result.stdout)
    assert match is not None, \
        f"Could not extract ACCURACY from the evaluator output.\nOutput was: {result.stdout}"
    accuracy = float(match.group(1))
    threshold = 0.85
    assert accuracy >= threshold, \
        f"Extracted accuracy {accuracy} is strictly less than the required threshold {threshold}."

    variant_raw = make_variant(original_raw)
    _, _, variant_selected = expected_selection(variant_raw)
    assert variant_selected != original_selected, "Internal test fixture did not change the selected features."

    try:
        with open(RAW_PATH, "wb") as raw_file:
            raw_file.write(variant_raw)
        run_script()
        with open(RAW_PATH, "rb") as raw_file:
            assert raw_file.read() == variant_raw, "prepare_data.sh must not modify raw_data.csv."
        validate_generated_csv(variant_raw)
    finally:
        with open(RAW_PATH, "wb") as raw_file:
            raw_file.write(original_raw)
        # Leave the requested artifact reproducibly generated from the real input.
        subprocess.run(["bash", SCRIPT_PATH], capture_output=True, text=True, timeout=60)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
