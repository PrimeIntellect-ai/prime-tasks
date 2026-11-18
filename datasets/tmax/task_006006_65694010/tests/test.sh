#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import csv
import json
import os
import subprocess

SOURCE = '/home/user/analyze.c'
INPUT = '/home/user/inference_logs.csv'
OUTPUT = '/home/user/analysis_result.json'
BINARY = '/tmp/analyze_verified'

assert os.path.isfile(SOURCE), f'Missing required C program file: {SOURCE}'

subprocess.run(
    ['gcc', '-std=c11', '-Wall', '-Wextra', SOURCE, '-o', BINARY],
    check=True,
    timeout=30,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), 'Compiled program is not executable'


def derive_expected(path):
    with open(path, newline='') as f:
        rows = list(csv.DictReader(f))
    assert rows, 'Inference log contains no data rows'

    parsed = []
    for row in rows:
        parsed.append({
            'temp_feature': int(row['temp_feature']),
            'pressure_feature': int(row['pressure_feature']),
            'actual_state': int(row['actual_state']),
            'predicted_state': int(row['predicted_state']),
        })

    candidates = []
    for feature in ('temp_feature', 'pressure_feature'):
        values = [row[feature] for row in parsed]
        for threshold in range(min(values) - 1, max(values) + 1):
            if all((1 if row[feature] > threshold else 0) == row['predicted_state'] for row in parsed):
                candidates.append((feature, threshold))

    assert len(candidates) == 1, f'Expected one uniquely reconstructable stump, found {candidates}'
    feature, threshold = candidates[0]
    accuracy = sum(row['predicted_state'] == row['actual_state'] for row in parsed) / len(parsed)
    return feature, threshold, accuracy


def expected_text(feature, threshold, accuracy):
    return (f'{{\n'
            f'  "feature": "{feature}",\n'
            f'  "threshold": {threshold},\n'
            f'  "accuracy": {accuracy:.3f}\n'
            f'}}')


def run_and_check(feature, threshold, accuracy):
    try:
        os.remove(OUTPUT)
    except FileNotFoundError:
        pass

    subprocess.run(
        [BINARY],
        cwd='/home/user',
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert os.path.isfile(OUTPUT), f'Missing required output file: {OUTPUT}'
    with open(OUTPUT) as f:
        content = f.read().strip().replace('\r\n', '\n')
    try:
        data = json.loads(content)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'The file {OUTPUT} does not contain valid JSON: {exc}')

    assert 'feature' in data, "Missing 'feature' key in JSON output."
    assert 'threshold' in data, "Missing 'threshold' key in JSON output."
    assert 'accuracy' in data, "Missing 'accuracy' key in JSON output."
    assert data['feature'] == feature, f"Expected feature {feature!r}, got {data['feature']!r}"
    assert data['threshold'] == threshold, f"Expected threshold {threshold}, got {data['threshold']!r}"
    assert abs(data['accuracy'] - accuracy) <= 0.001, f"Expected accuracy ~{accuracy:.3f}, got {data['accuracy']!r}"

    expected = expected_text(feature, threshold, accuracy)
    assert content == expected, f'JSON formatting does not exactly match.\nExpected:\n{expected}\nGot:\n{content}'


def write_case(target_feature, threshold, flip_mod):
    with open(INPUT, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['timestamp', 'temp_feature', 'pressure_feature', 'actual_state', 'predicted_state'])
        for i in range(202):
            value = i % 101
            if target_feature == 'pressure_feature':
                pressure, temp = value, 100 - value
                predicted = int(pressure > threshold)
            else:
                temp, pressure = value, 100 - value
                predicted = int(temp > threshold)
            actual = 1 - predicted if i % flip_mod == 0 else predicted
            writer.writerow([1700000000 + i, temp, pressure, actual, predicted])


with open(INPUT, 'rb') as f:
    original_input = f.read()

try:
    # Exercise the submitted program on independently checked inputs so a source
    # file that merely emits the known final JSON cannot pass.
    for target_feature, threshold, flip_mod in (
        ('pressure_feature', 37, 7),
        ('temp_feature', 12, 11),
    ):
        write_case(target_feature, threshold, flip_mod)
        derived = derive_expected(INPUT)
        run_and_check(*derived)
finally:
    with open(INPUT, 'wb') as f:
        f.write(original_input)

# Recompute the answer from the real log, execute the program against that log,
# and leave its freshly generated result in the required final location.
original_expected = derive_expected(INPUT)
run_and_check(*original_expected)

# Preserve the original verifier's fixed assertions for the shipped data.
with open(OUTPUT) as f:
    final_content = f.read().strip().replace('\r\n', '\n')
final_data = json.loads(final_content)
assert final_data['feature'] == 'pressure_feature', f"Expected feature 'pressure_feature', got {final_data['feature']!r}"
assert final_data['threshold'] == 73, f"Expected threshold 73, got {final_data['threshold']!r}"
assert abs(final_data['accuracy'] - 0.916) <= 0.001, f"Expected accuracy ~0.916, got {final_data['accuracy']!r}"
fixed_expected = '{\n  "feature": "pressure_feature",\n  "threshold": 73,\n  "accuracy": 0.916\n}'
assert final_content == fixed_expected, f'JSON formatting does not exactly match.\nExpected:\n{fixed_expected}\nGot:\n{final_content}'
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
