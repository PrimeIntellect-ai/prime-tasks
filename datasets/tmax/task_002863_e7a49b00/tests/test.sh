#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess

CSV_PATH = '/home/user/data/raw.csv'
PRED_PATH = '/home/user/predictions.txt'
SCRIPT_PATH = '/home/user/etl.sh'


def expected_predictions(data):
    train_data = data[:80]
    test_data = data[80:]
    mins = [min(row[c] for row in train_data) for c in range(3)]
    maxs = [max(row[c] for row in train_data) for c in range(3)]

    expected = []
    for row in test_data:
        scaled = [
            (row[c] - mins[c]) / (maxs[c] - mins[c])
            for c in range(3)
        ]
        expected.append(5.0 + 2.5 * scaled[0] + 0.5 * scaled[1] - 1.2 * scaled[2])
    return expected


def write_dataset(data):
    with open(CSV_PATH, 'w') as f:
        f.write('age,income,score\n')
        for row in data:
            f.write(','.join(str(value) for value in row) + '\n')


def run_etl_and_read_predictions():
    if os.path.lexists(PRED_PATH):
        os.remove(PRED_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'etl.sh exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\n'
        f'stderr:\n{result.stderr}'
    )
    assert os.path.isfile(PRED_PATH), 'Running etl.sh did not create predictions.txt.'

    with open(PRED_PATH, 'r') as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 20, f'Expected exactly 20 prediction lines, found {len(lines)}.'

    values = []
    for i, line in enumerate(lines, 1):
        try:
            value = float(line)
        except ValueError:
            assert False, f"Prediction at line {i} is not a valid float: '{line}'"
        assert math.isfinite(value), f'Prediction at line {i} is not finite.'
        values.append(value)
    return values


def make_probe(train_ranges, test_ranges):
    rng = random.SystemRandom()
    train = [[rng.randint(lo, hi) for lo, hi in train_ranges] for _ in range(80)]
    # Ensure every training extrema is known and represented.
    train[0] = [bounds[0] for bounds in train_ranges]
    train[1] = [bounds[1] for bounds in train_ranges]

    test = [[rng.randint(lo, hi) for lo, hi in test_ranges] for _ in range(20)]
    # Put values outside the training extrema in the held-out portion. A pipeline
    # using global extrema will therefore produce different predictions.
    test[0] = [bounds[0] for bounds in test_ranges]
    test[1] = [bounds[1] for bounds in test_ranges]
    return train + test


def test_etl_script_executes_and_uses_training_extrema():
    assert os.path.isfile(SCRIPT_PATH), f'The file {SCRIPT_PATH} is missing.'
    assert os.access(SCRIPT_PATH, os.X_OK), f'The file {SCRIPT_PATH} is not executable.'
    with open(SCRIPT_PATH, 'rb') as f:
        first_line = f.readline(256).decode('utf-8', errors='replace').lower()
    assert first_line.startswith('#!') and 'bash' in first_line, 'etl.sh must be an executable Bash script.'

    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()

    probes = [
        make_probe(
            [(30, 60), (50000, 90000), (60, 90)],
            [(8, 93), (12000, 145000), (25, 119)],
        ),
        make_probe(
            [(18, 47), (31000, 71000), (72, 98)],
            [(-4, 81), (5000, 130000), (40, 125)],
        ),
    ]

    try:
        for probe_number, data in enumerate(probes, 1):
            write_dataset(data)
            actual = run_etl_and_read_predictions()
            expected = expected_predictions(data)
            for i, (got, want) in enumerate(zip(actual, expected), 1):
                assert abs(got - want) < 1e-4, (
                    f'Probe {probe_number}, prediction {i} is incorrect. '
                    f'Expected {want}, got {got}. The scaler must derive extrema '
                    'only from the first 80 data rows.'
                )
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        # Re-run against the supplied dataset so the original final-state checks
        # below validate the artifact's normal output.
        if os.path.exists(SCRIPT_PATH) and os.access(SCRIPT_PATH, os.X_OK):
            if os.path.lexists(PRED_PATH):
                os.remove(PRED_PATH)
            subprocess.run(
                [SCRIPT_PATH],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )


def test_predictions_exist():
    """Check if the predictions file exists."""
    assert os.path.isfile('/home/user/predictions.txt'), "The file /home/user/predictions.txt is missing."


def test_predictions_correctness():
    """Verify the predictions are correctly calculated without data leakage."""
    csv_path = '/home/user/data/raw.csv'
    pred_path = '/home/user/predictions.txt'

    assert os.path.isfile(csv_path), f"The file {csv_path} is missing."
    assert os.path.isfile(pred_path), f"The file {pred_path} is missing."

    with open(csv_path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 101, "Expected exactly 101 lines in raw.csv (header + 100 rows)."

    data = []
    for line in lines[1:]:
        parts = line.split(',')
        assert len(parts) == 3, "Invalid CSV format."
        data.append([float(parts[0]), float(parts[1]), float(parts[2])])

    train_data = data[:80]
    test_data = data[80:]
    assert len(test_data) == 20, "Expected exactly 20 test rows."

    min_age = min(row[0] for row in train_data)
    max_age = max(row[0] for row in train_data)
    min_income = min(row[1] for row in train_data)
    max_income = max(row[1] for row in train_data)
    min_score = min(row[2] for row in train_data)
    max_score = max(row[2] for row in train_data)

    expected_preds = []
    for row in test_data:
        scaled_age = (row[0] - min_age) / (max_age - min_age)
        scaled_income = (row[1] - min_income) / (max_income - min_income)
        scaled_score = (row[2] - min_score) / (max_score - min_score)
        pred = 5.0 + (2.5 * scaled_age) + (0.5 * scaled_income) + (-1.2 * scaled_score)
        expected_preds.append(pred)

    with open(pred_path, 'r') as f:
        actual_lines = f.read().strip().split('\n')

    assert len(actual_lines) == 20, f"Expected exactly 20 lines in predictions.txt, found {len(actual_lines)}."

    for i, (actual_str, expected) in enumerate(zip(actual_lines, expected_preds)):
        try:
            actual = float(actual_str)
        except ValueError:
            assert False, f"Prediction at line {i+1} is not a valid float: '{actual_str}'"

        diff = abs(actual - expected)
        assert diff < 1e-4, (
            f"Prediction mismatch at line {i+1} (test row {i+81}).\n"
            f"Expected: {expected}\n"
            f"Actual: {actual}\n"
            f"Difference: {diff}\n"
            "Ensure min/max are calculated ONLY on the first 80 rows and applied correctly."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
