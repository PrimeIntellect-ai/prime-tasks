#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

SCRIPT_PATH = '/home/user/analyze.sh'
INPUT_PATH = '/home/user/trials.csv'
OUTPUT_PATH = '/home/user/priors.tsv'


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(['bash', SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found: {OUTPUT_PATH}"
    with open(OUTPUT_PATH, 'rb') as f:
        return f.read()


def test_analyze_script_exists():
    """Check if the analyze script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found: {SCRIPT_PATH}"


def test_analyze_script_execution_and_output():
    """Retain the original fixed-dataset execution and content assertions."""
    actual_content = run_script().decode()
    expected_content = "alpha\t0.5926\nbeta\t0.3438\ngamma\t0.4815\n"

    expected_lines = [line.strip() for line in expected_content.strip().split('\n')]
    actual_lines = [line.strip() for line in actual_content.strip().split('\n')]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, got {len(actual_lines)}"
    for expected, actual in zip(expected_lines, actual_lines):
        assert actual == expected, f"Expected line '{expected}', but got '{actual}'"


def rounded_mean(successes, total):
    numerator = (successes + 1) * 10000
    denominator = total + 2
    whole, remainder = divmod(numerator, denominator)
    assert remainder * 2 != denominator
    if remainder * 2 > denominator:
        whole += 1
    return f"{whole // 10000}.{whole % 10000:04d}"


def write_dataset(training_rows, test_rows):
    assert len(training_rows) == 80
    assert len(test_rows) == 20
    with open(INPUT_PATH, 'w', newline='') as f:
        f.write('id,group,success\n')
        for idx, (group, success) in enumerate(training_rows + test_rows, 1):
            f.write(f'{idx},{group},{success}\n')


def expected_output(training_rows):
    counts = {}
    for group, success in training_rows:
        if group not in counts:
            counts[group] = [0, 0]
        counts[group][0] += success
        counts[group][1] += 1
    return ''.join(
        f'{group}\t{rounded_mean(counts[group][0], counts[group][1])}\n'
        for group in sorted(counts)
    ).encode()


def test_randomized_transformation_and_test_set_isolation():
    """Exercise fresh inputs and prove that rows 82-101 cannot affect priors."""
    with open(INPUT_PATH, 'rb') as f:
        original_input = f.read()

    rng = secrets.SystemRandom()
    try:
        for _ in range(2):
            groups = [f'grp_{secrets.token_hex(5)}' for _ in range(4)]
            training = []
            for group in groups:
                training.extend((group, rng.randrange(2)) for _ in range(20))
            rng.shuffle(training)

            expected = expected_output(training)
            suffix_one = [(f'test_only_{secrets.token_hex(4)}', 1) for _ in range(20)]
            suffix_two = [(f'other_test_{secrets.token_hex(4)}', 0) for _ in range(20)]

            write_dataset(training, suffix_one)
            first = run_script()
            assert first == expected, (
                f'Incorrect output for randomized training data.\n'
                f'Expected: {expected!r}\nActual: {first!r}'
            )

            write_dataset(training, suffix_two)
            second = run_script()
            assert second == expected, (
                f'Changing only the final 20 test rows changed or corrupted the result.\n'
                f'Expected: {expected!r}\nActual: {second!r}'
            )
            assert second == first, 'Output depends on rows after the first 80 data rows'
    finally:
        with open(INPUT_PATH, 'wb') as f:
            f.write(original_input)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
