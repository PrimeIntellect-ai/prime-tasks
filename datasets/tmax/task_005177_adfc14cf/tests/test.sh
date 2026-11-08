#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
import pytest

PROJECT_DIR = '/home/user/risk_pipeline'
RECORDS_PATH = '/home/user/data/records.csv'
PREDICTIONS_PATH = '/home/user/risk_pipeline/predictions.csv'

CANONICAL_INPUT = '''id,age,income,category
1,25,60000,A
2,45,120000,C
3,30,45000,B
4,50,80000,A
5,22,35000,C
'''

EXPECTED_CONTENT = [
    'id,score',
    '1,2.525',
    '2,2.625',
    '3,0.550',
    '4,3.050',
    '5,0.810',
]


def run_pipeline():
    try:
        result = subprocess.run(
            ['cargo', 'run', '--quiet'],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except FileNotFoundError:
        pytest.fail("Error: 'cargo' command not found. Is Rust installed?")
    except subprocess.TimeoutExpired:
        pytest.fail("Error: 'cargo run' timed out.")

    assert result.returncode == 0, (
        f"Error: Cargo program failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )


def write_records(rows):
    with open(RECORDS_PATH, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['id', 'age', 'income', 'category'])
        writer.writerows(rows)


def test_cargo_tests_pass():
    """Check that this is a runnable Cargo project and its tests pass."""
    assert os.path.isdir(PROJECT_DIR), f"Error: Cargo project directory {PROJECT_DIR} not found."
    assert os.path.isfile(os.path.join(PROJECT_DIR, 'Cargo.toml')), 'Cargo.toml not found.'
    assert os.path.isfile(os.path.join(PROJECT_DIR, 'src', 'main.rs')), 'src/main.rs not found.'

    try:
        result = subprocess.run(
            ['cargo', 'test'],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except FileNotFoundError:
        pytest.fail("Error: 'cargo' command not found. Is Rust installed?")
    except subprocess.TimeoutExpired:
        pytest.fail("Error: 'cargo test' timed out.")

    assert result.returncode == 0, (
        f"Error: Cargo tests failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert 'test_reproducibility' in result.stdout or 'test_reproducibility' in result.stderr, \
        "Error: 'test_reproducibility' not found in test execution output."


def test_predictions_csv_content_generated_by_program():
    """Run the submitted program and retain the original exact-output assertion."""
    with open(RECORDS_PATH, 'w') as f:
        f.write(CANONICAL_INPUT)
    if os.path.exists(PREDICTIONS_PATH):
        os.remove(PREDICTIONS_PATH)

    run_pipeline()
    assert os.path.isfile(PREDICTIONS_PATH), f"Error: {PREDICTIONS_PATH} not found."

    with open(PREDICTIONS_PATH, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == EXPECTED_CONTENT, \
        f"Content of {PREDICTIONS_PATH} does not match the expected output."


def test_pipeline_reads_input_and_computes_scores():
    """Exercise the executable on unpredictable records and derive the answers."""
    rng = random.SystemRandom()
    categories = ['A', 'B', 'C']
    rows = []
    for index in range(9):
        record_id = rng.randrange(100000, 1000000000)
        age = rng.randrange(9, 51) * 2
        income = rng.randrange(1, 201) * 1000
        category = categories[index % 3]
        rows.append((record_id, age, income, category))
    rng.shuffle(rows)

    expected = []
    for record_id, age, income, category in rows:
        is_a = 1.0 if category == 'A' else 0.0
        is_b = 1.0 if category == 'B' else 0.0
        score = (0.5 * (age / 100.0)) + (2.0 * (income / 100000.0)) + (1.2 * is_a) - (0.5 * is_b)
        expected.append([str(record_id), f'{score:.3f}'])

    try:
        write_records(rows)
        if os.path.exists(PREDICTIONS_PATH):
            os.remove(PREDICTIONS_PATH)
        run_pipeline()

        assert os.path.isfile(PREDICTIONS_PATH), \
            'Program did not create predictions.csv for the supplied input.'
        with open(PREDICTIONS_PATH, newline='') as f:
            actual = list(csv.reader(f))

        assert actual and actual[0] == ['id', 'score'], \
            "predictions.csv must have exactly the header 'id,score'."
        assert all(len(row) == 2 for row in actual), \
            'predictions.csv must contain exactly two columns.'
        assert actual[1:] == expected, \
            f'Program did not compute the expected scores from records.csv. Expected {expected}, got {actual[1:]}.'
    finally:
        with open(RECORDS_PATH, 'w') as f:
            f.write(CANONICAL_INPUT)
        if os.path.isdir(PROJECT_DIR):
            subprocess.run(
                ['cargo', 'run', '--quiet'], cwd=PROJECT_DIR,
                capture_output=True, text=True, timeout=60,
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
