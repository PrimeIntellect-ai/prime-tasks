#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'CPP_EOF' > /tmp/bootstrap_indices.cpp
#include <cstddef>
#include <cstdlib>
#include <iostream>
#include <random>

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    const std::size_t n0 = static_cast<std::size_t>(std::stoull(argv[1]));
    const std::size_t n1 = static_cast<std::size_t>(std::stoull(argv[2]));
    if (n0 == 0 || n1 == 0) return 1;

    std::mt19937 gen(42);
    std::uniform_int_distribution<std::size_t> dist0(0, n0 - 1);
    std::uniform_int_distribution<std::size_t> dist1(0, n1 - 1);

    for (int i = 0; i < 1000; ++i) std::cout << "0," << dist0(gen) << '\n';
    for (int i = 0; i < 1000; ++i) std::cout << "1," << dist1(gen) << '\n';
    return 0;
}
CPP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import csv
import subprocess
import pytest

RAW_DATA_PATH = "/home/user/data/raw_data.csv"
PREPARED_DATA_PATH = "/home/user/data/prepared_data.csv"
METRICS_PATH = "/home/user/data/metrics.txt"
INDEX_HELPER_PATH = "/tmp/bootstrap_indices"


def load_raw_data():
    with open(RAW_DATA_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    return header, rows


def compute_t_stats():
    with open(RAW_DATA_PATH, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)

        # Group data by label
        data_0 = {col: [] for col in header[2:]}
        data_1 = {col: [] for col in header[2:]}

        for row in reader:
            label = int(row[1])
            for i, col in enumerate(header[2:]):
                if label == 0:
                    data_0[col].append(float(row[i+2]))
                else:
                    data_1[col].append(float(row[i+2]))

    t_stats = []
    for col in header[2:]:
        n0 = len(data_0[col])
        n1 = len(data_1[col])

        mean0 = sum(data_0[col]) / n0
        mean1 = sum(data_1[col]) / n1

        var0 = sum((x - mean0)**2 for x in data_0[col]) / (n0 - 1)
        var1 = sum((x - mean1)**2 for x in data_1[col]) / (n1 - 1)

        t_stat = abs(mean1 - mean0) / math.sqrt((var1 / n1) + (var0 / n0))
        t_stats.append((col, t_stat))

    t_stats.sort(key=lambda x: x[1], reverse=True)
    return t_stats[:3]


def expected_bootstrap_rows(expected_top3):
    header, raw_rows = load_raw_data()
    rows_0 = [row for row in raw_rows if int(row[1]) == 0]
    rows_1 = [row for row in raw_rows if int(row[1]) == 1]

    result = subprocess.run(
        [INDEX_HELPER_PATH, str(len(rows_0)), str(len(rows_1))],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    selections = [line.split(',') for line in result.stdout.splitlines() if line]
    assert len(selections) == 2000

    feature_positions = [header.index(feature) for feature, _ in expected_top3]
    expected = []
    for label_text, index_text in selections:
        label = int(label_text)
        index = int(index_text)
        source = rows_0[index] if label == 0 else rows_1[index]
        expected.append([
            source[0],
            source[1],
            source[feature_positions[0]],
            source[feature_positions[1]],
            source[feature_positions[2]],
        ])
    return expected


def test_metrics_file():
    assert os.path.exists(METRICS_PATH), f"File {METRICS_PATH} does not exist."

    expected_top3 = compute_t_stats()

    with open(METRICS_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in {METRICS_PATH}, found {len(lines)}."

    for i, (expected_feat, expected_t) in enumerate(expected_top3):
        parts = lines[i].split(":")
        assert len(parts) == 2, f"Invalid format in {METRICS_PATH} on line {i+1}."
        feat = parts[0].strip()
        t_val = float(parts[1].strip())

        assert feat == expected_feat, f"Expected feature {expected_feat} at rank {i+1}, found {feat}."
        assert abs(t_val - expected_t) < 0.0005, f"Expected t-stat {expected_t:.4f} for {feat}, found {t_val}."


def test_prepared_data_file():
    assert os.path.exists(PREPARED_DATA_PATH), f"File {PREPARED_DATA_PATH} does not exist."

    expected_top3 = compute_t_stats()
    expected_header = f"id,label,{expected_top3[0][0]},{expected_top3[1][0]},{expected_top3[2][0]}"

    with open(PREPARED_DATA_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2001, f"Expected 2001 lines in {PREPARED_DATA_PATH}, found {len(lines)}."
    assert lines[0] == expected_header, f"Expected header '{expected_header}', found '{lines[0]}'."

    # Check class balance
    label_0_count = 0
    label_1_count = 0
    for line in lines[1:]:
        parts = line.split(",")
        label = int(parts[1])
        if label == 0:
            label_0_count += 1
        elif label == 1:
            label_1_count += 1

    assert label_0_count == 1000, f"Expected 1000 records for label 0, found {label_0_count}."
    assert label_1_count == 1000, f"Expected 1000 records for label 1, found {label_1_count}."

    expected_rows = expected_bootstrap_rows(expected_top3)
    actual_rows = [line.split(',') for line in lines[1:]]

    for row_number, (actual, expected) in enumerate(zip(actual_rows, expected_rows), start=2):
        assert len(actual) == 5, f"Expected 5 columns on line {row_number}, found {len(actual)}."
        assert actual[0] == expected[0], f"Incorrect sampled id on line {row_number}."
        assert actual[1] == expected[1], f"Incorrect sampled label on line {row_number}."
        for column in range(2, 5):
            try:
                actual_value = float(actual[column])
                expected_value = float(expected[column])
            except ValueError:
                pytest.fail(f"Non-numeric feature value on line {row_number}, column {column + 1}.")
            assert math.isfinite(actual_value), f"Non-finite feature value on line {row_number}, column {column + 1}."
            assert math.isclose(actual_value, expected_value, rel_tol=1e-5, abs_tol=1e-6), \
                f"Incorrect feature value on line {row_number}, column {column + 1}."
TEST_EOF

if g++ -std=c++17 -O2 /tmp/bootstrap_indices.cpp -o /tmp/bootstrap_indices && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
