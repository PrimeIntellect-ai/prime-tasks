#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import math
import os
import re
import secrets
import subprocess

INPUT_PATH = '/home/user/artifacts/embeddings.csv'
SCRIPT_PATH = '/home/user/process.sh'
OUTPUT_PATH = '/home/user/processed_norms.csv'
ORIGINAL_INPUT = "id,f1,f2,f3\nexp1,2.0,2.0,1.0\nexp2,6.0,8.0,1.1\nexp3,3.0,5.0,0.9\nexp4,5.0,3.0,1.2"


def test_embeddings_file_exists():
    """Check if the input embeddings file exists."""
    assert os.path.isfile('/home/user/artifacts/embeddings.csv'), "The /home/user/artifacts/embeddings.csv file is missing."


def test_embeddings_file_contents():
    """Check that the required raw embeddings were created exactly."""
    with open(INPUT_PATH, 'r') as f:
        content = f.read().strip()
    assert content == ORIGINAL_INPUT, f"The content of {INPUT_PATH} does not match the required input data."


def test_process_script_exists_and_executable():
    """Check if the process script exists and is executable."""
    script_path = '/home/user/process.sh'
    assert os.path.isfile(script_path), f"The script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_process_script_output():
    """Run the script and verify the output matches the expected L2 norms."""
    script_path = '/home/user/process.sh'
    output_path = '/home/user/processed_norms.csv'

    # Run the script to ensure it generates the correct file
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    assert os.path.isfile(output_path), f"The output file {output_path} was not generated."

    with open(output_path, 'r') as f:
        content = f.read().strip()

    expected_content = "id,l2_norm\nexp1,3.20\nexp2,4.03\nexp3,1.12\nexp4,1.80"

    assert content == expected_content, f"The content of {output_path} does not match the expected output.\nExpected:\n{expected_content}\nGot:\n{content}"


def make_random_case(case_number):
    """Create an unpredictable four-row input and derive its correct result."""
    rng = secrets.SystemRandom()
    while True:
        values = [[rng.randint(-120, 120) / 10.0 for _ in range(3)] for _ in range(4)]
        means = [sum(row[j] for row in values) / 4.0 for j in range(3)]
        variances = [sum((row[j] - means[j]) ** 2 for row in values) / 4.0 for j in range(3)]
        ordered = sorted(variances)
        if ordered[1] - ordered[0] < 0.5:
            continue
        dropped = variances.index(min(variances))
        kept = [j for j in range(3) if j != dropped]
        norms = [math.sqrt(sum((row[j] - means[j]) ** 2 for j in kept)) for row in values]
        # Avoid values extremely close to a rounding tie, where platform printf
        # implementations can legitimately differ in their tie-breaking rule.
        if all(abs((norm * 100.0) % 1.0 - 0.5) > 0.01 for norm in norms):
            break

    token = secrets.token_hex(4)
    ids = [f"case{case_number}_{token}_row{i}" for i in range(4)]
    lines = ['id,f1,f2,f3']
    for row_id, row in zip(ids, values):
        lines.append(row_id + ',' + ','.join(f'{value:.1f}' for value in row))
    return '\n'.join(lines) + '\n', ids, norms


def test_process_script_uses_input_and_performs_pipeline():
    """Exercise the submitted script on inputs whose answers are derived here."""
    for case_number in range(4):
        csv_input, ids, expected_norms = make_random_case(case_number)
        with open(INPUT_PATH, 'w') as f:
            f.write(csv_input)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Script failed on generated input: {result.stderr}"
        assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} was not generated."

        with open(OUTPUT_PATH, 'r') as f:
            lines = f.read().strip().splitlines()
        assert len(lines) == 5, f"Expected a header and 4 result rows, got: {lines}"
        assert lines[0] == 'id,l2_norm', f"Incorrect output header: {lines[0] if lines else '<missing>'}"

        for line, expected_id, expected_norm in zip(lines[1:], ids, expected_norms):
            match = re.fullmatch(re.escape(expected_id) + r',([0-9]+\.[0-9]{2})', line)
            assert match, f"Malformed output row or incorrect id: {line}"
            expected_text = f'{expected_norm:.2f}'
            assert match.group(1) == expected_text, (
                f"Incorrect norm for {expected_id}: expected {expected_text}, got {match.group(1)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
