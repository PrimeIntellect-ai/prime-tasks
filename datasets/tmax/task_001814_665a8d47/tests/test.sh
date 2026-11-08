#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import random
import secrets
import subprocess


def compute_expected_values(csv_path):
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        data = {'F1': [], 'F2': [], 'F3': [], 'F4': [], 'T': []}
        for row in reader:
            for col in data.keys():
                data[col].append(float(row[col]))

    n = len(data['T'])
    target = data['T']
    mean_T = sum(target) / n

    best_feature = None
    best_corr_abs = -1
    best_corr_val = 0
    best_w = 0
    best_b = 0

    features = ['F1', 'F2', 'F3', 'F4']
    for f in features:
        feature_data = data[f]
        mean_F = sum(feature_data) / n

        num = 0.0
        den_F = 0.0
        den_T = 0.0

        for i in range(n):
            diff_F = feature_data[i] - mean_F
            diff_T = target[i] - mean_T
            num += diff_F * diff_T
            den_F += diff_F ** 2
            den_T += diff_T ** 2

        corr = num / math.sqrt(den_F * den_T)

        if abs(corr) > best_corr_abs:
            best_corr_abs = abs(corr)
            best_corr_val = corr
            best_feature = f
            best_w = num / den_F
            best_b = mean_T - best_w * mean_F

    return best_feature, best_corr_val, best_w, best_b


def expected_output(csv_path):
    best_feature, best_corr_val, best_w, best_b = compute_expected_values(csv_path)
    return (
        f"SelectedFeature: {best_feature}\n"
        f"Correlation: {best_corr_val:.4f}\n"
        f"Weight: {best_w:.4f}\n"
        f"Bias: {best_b:.4f}"
    )


def run_pipeline():
    output_path = '/home/user/etl_model_output.txt'
    if os.path.exists(output_path):
        os.remove(output_path)
    result = subprocess.run(
        ['/home/user/pipeline'],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(output_path), "Executing the pipeline did not create the output file."


def test_pipeline_cpp_exists():
    """Check if the C++ source file exists."""
    assert os.path.exists('/home/user/pipeline.cpp'), "The source file /home/user/pipeline.cpp is missing."


def test_pipeline_binary_exists():
    """Check if the compiled binary exists and is executable."""
    binary_path = '/home/user/pipeline'
    assert os.path.exists(binary_path), f"The compiled binary {binary_path} is missing."
    assert os.access(binary_path, os.X_OK), f"The file {binary_path} is not executable."


def test_compile_and_execute_pipeline():
    """Compile the submitted source and execute that freshly built artifact."""
    result = subprocess.run(
        ['g++', '-O3', '-std=c++17', '/home/user/pipeline.cpp', '-o', '/home/user/pipeline'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pipeline.cpp failed to compile.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.access('/home/user/pipeline', os.X_OK), "Freshly compiled pipeline is not executable."
    run_pipeline()


def test_etl_model_output():
    """Check if the output file matches the expected calculations."""
    output_path = '/home/user/etl_model_output.txt'
    csv_path = '/home/user/sensor_data.csv'

    assert os.path.exists(output_path), f"The output file {output_path} is missing."
    assert os.path.exists(csv_path), f"The dataset file {csv_path} is missing."

    best_feature, best_corr_val, best_w, best_b = compute_expected_values(csv_path)

    expected = (
        f"SelectedFeature: {best_feature}\n"
        f"Correlation: {best_corr_val:.4f}\n"
        f"Weight: {best_w:.4f}\n"
        f"Bias: {best_b:.4f}"
    )

    with open(output_path, 'r') as f:
        actual_output = f.read().strip()

    assert actual_output == expected, f"Output mismatch.\nExpected:\n{expected}\n\nGot:\n{actual_output}"


def test_pipeline_on_unseen_microbatches():
    """Exercise the compiled source on unpredictable datasets with different selected features."""
    csv_path = '/home/user/sensor_data.csv'
    output_path = '/home/user/etl_model_output.txt'

    with open(csv_path, 'rb') as f:
        original_csv = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, 'rb') as f:
            original_output = f.read()

    rng = random.Random(secrets.randbits(128))
    features = ['F1', 'F2', 'F3', 'F4']

    try:
        for case_index, selected in enumerate(features):
            rows = []
            coefficient = -6.25 if case_index % 2 == 0 else 4.75
            bias = rng.uniform(-8.0, 8.0)

            for _ in range(211 + case_index * 7):
                values = {
                    'F1': rng.gauss(-1.5, 1.1),
                    'F2': rng.gauss(4.0, 2.3),
                    'F3': rng.gauss(-3.0, 1.7),
                    'F4': rng.gauss(9.0, 4.2),
                }
                target = coefficient * values[selected] + bias + rng.gauss(0.0, 0.18)
                rows.append([values['F1'], values['F2'], values['F3'], values['F4'], target])

            with open(csv_path, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['F1', 'F2', 'F3', 'F4', 'T'])
                writer.writerows(rows)

            expected = expected_output(csv_path)
            assert expected.startswith(f"SelectedFeature: {selected}\n"), "Generated test case was not sufficiently discriminating."

            run_pipeline()
            with open(output_path, 'r') as f:
                actual = f.read().strip()
            assert actual == expected, (
                f"Pipeline failed on an unseen dataset where {selected} should be selected.\n"
                f"Expected:\n{expected}\n\nGot:\n{actual}"
            )
    finally:
        with open(csv_path, 'wb') as f:
            f.write(original_csv)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
