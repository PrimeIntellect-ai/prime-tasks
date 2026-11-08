#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess


def compute_expected_output(input_path):
    expected_rows = [['category', 'normalized_text', 'token_count', 'rolling_avg']]
    category_counts = {}
    category_prev_tokens = {}

    with open(input_path, 'r') as f:
        for line in f:
            if not line.strip("\n"):
                continue
            parts = line.strip("\n").split('\t')
            if len(parts) != 2:
                continue
            category, raw_text = parts

            if category_counts.get(category, 0) >= 3:
                continue

            normalized = re.sub(r'[^a-z0-9 ]', '', raw_text.lower())
            tokens = [t for t in normalized.split(' ') if t]
            normalized_text = ' '.join(tokens)
            token_count = len(tokens)

            if category not in category_prev_tokens:
                rolling_avg = float(token_count)
            else:
                rolling_avg = (token_count + category_prev_tokens[category]) / 2.0

            category_prev_tokens[category] = token_count
            category_counts[category] = category_counts.get(category, 0) + 1
            expected_rows.append([
                category,
                normalized_text,
                str(token_count),
                f"{rolling_avg:.1f}",
            ])

    return expected_rows


def assert_output_correct(input_file, output_file):
    assert os.path.exists(input_file), f"Input file {input_file} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} was not created."

    expected_data = compute_expected_output(input_file)
    with open(output_file, 'r') as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, "Output CSV is empty."
    assert reader[0] == expected_data[0], (
        f"CSV headers do not match. Expected {expected_data[0]}, got {reader[0]}"
    )
    assert len(reader) == len(expected_data), (
        f"Output CSV has incorrect number of rows. Expected {len(expected_data)}, got {len(reader)}"
    )
    for i, (actual, expected) in enumerate(zip(reader, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"


def run_process(script_file, output_file):
    if os.path.lexists(output_file):
        os.remove(output_file)
    result = subprocess.run(
        ['python3', script_file],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"process.py exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.exists(output_file), "process.py did not create /home/user/output.csv"


def test_output_csv_exists_and_correct_and_script_is_executable():
    input_file = '/home/user/input.tsv'
    output_file = '/home/user/output.csv'
    script_file = '/home/user/process.py'

    # Preserve all original checks against the supplied input and submitted output.
    assert_output_correct(input_file, output_file)

    assert os.path.isfile(script_file), f"Required script {script_file} is missing or not a regular file."
    assert os.path.getsize(script_file) > 0, f"Required script {script_file} is empty."

    with open(input_file, 'rb') as f:
        original_input = f.read()
    with open(output_file, 'rb') as f:
        original_output = f.read()

    try:
        # Verify that the script itself reproduces the result for the supplied input.
        run_process(script_file, output_file)
        assert_output_correct(input_file, output_file)

        # Exercise the implementation on a fresh, unpredictable input so a fixed
        # output cannot satisfy the verifier.
        left = secrets.token_hex(6)
        right = secrets.token_hex(6)
        cat1 = 'cat_' + secrets.token_hex(4)
        cat2 = 'group_' + secrets.token_hex(4)
        cat3 = 'third_' + secrets.token_hex(4)
        rows = [
            (cat1, f'  ALPHA-{left}!  99?? '),
            (cat2, f'*** {right.upper()}...   MIX_ed'),
            (cat1, f'one   two,{left}  '),
            (cat3, f'({right})'),
            (cat1, '!!!'),
            (cat2, f'A+B C/D   {left}'),
            (cat1, 'this fourth row must be discarded'),
            (cat2, ' spaced    words '),
            (cat3, f'X-{left}-Y'),
            (cat2, 'this fourth row must also be discarded'),
        ]
        with open(input_file, 'w', newline='') as f:
            for category, raw_text in rows:
                f.write(f'{category}\t{raw_text}\n')

        run_process(script_file, output_file)
        assert_output_correct(input_file, output_file)
    finally:
        with open(input_file, 'wb') as f:
            f.write(original_input)
        with open(output_file, 'wb') as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
