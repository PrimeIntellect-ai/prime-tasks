#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import ast
import csv
import os
import random
import re
import secrets
import stat
import subprocess

import pandas as pd

SCRIPT = '/home/user/process_feedback.py'
RAW = '/home/user/raw_surveys.csv'
FINAL = '/home/user/final_surveys.csv'
LOG = '/home/user/pipeline.log'


def run_pipeline():
    for path in (FINAL, LOG):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'process_feedback.py failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def normalize(value):
    value = str(value).lower()
    value = re.sub(r'[^a-z0-9 ]', '', value)
    value = re.sub(r' +', ' ', value)
    return value.strip()


def derive_expected(rows):
    melted = []
    for question in ('q1_response', 'q2_response', 'q3_response'):
        for row in rows:
            value = row[question]
            if value is None or value == '':
                continue
            melted.append((row['user_id'], row['age'], question, normalize(value)))

    seen = set()
    cleaned = []
    for user_id, age, question, text in melted:
        key = (user_id, question)
        if key not in seen:
            seen.add(key)
            cleaned.append((user_id, age, question, text))
    cleaned.sort(key=lambda item: (item[0], item[2]))
    return cleaned


def assert_dynamic_output(expected, melted_count):
    assert os.path.exists(FINAL), f'File {FINAL} is missing.'
    assert os.path.isfile(FINAL), f'{FINAL} is not a file.'
    with open(FINAL, newline='') as f:
        reader = csv.reader(f)
        actual = list(reader)

    expected_csv = [['user_id', 'age', 'question_id', 'normalized_text']]
    expected_csv.extend([[str(v) for v in row] for row in expected])
    assert actual == expected_csv, f'Dynamic output mismatch. Expected {expected_csv!r}, got {actual!r}'

    assert os.path.exists(LOG), f'Log file {LOG} is missing.'
    assert os.path.isfile(LOG), f'{LOG} is not a file.'
    with open(LOG) as f:
        content = f.read()
    for message in (
        'Pipeline started',
        f'Melted data: {melted_count} rows',
        f'Cleaned data: {len(expected)} rows',
        'Pipeline completed',
    ):
        assert message in content, f"Expected log message '{message}' not found in {LOG}"


def assert_original_output():
    # Preserve the original verifier's exact final CSV assertions.
    assert os.path.exists(FINAL), f'File {FINAL} is missing.'
    assert os.path.isfile(FINAL), f'{FINAL} is not a file.'
    expected_content = [
        'user_id,age,question_id,normalized_text',
        '1,25,q1_response,great product',
        '1,25,q2_response,too expensive',
        '2,34,q1_response,needs work',
        '2,34,q3_response,no comment',
        '3,45,q2_response,okay',
        '3,45,q3_response,very badexperience',
        '4,29,q1_response,awesome',
        '4,29,q2_response,loved it',
        '4,29,q3_response,yes',
    ]
    with open(FINAL) as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) == len(expected_content), (
        f'Expected {len(expected_content)} lines in final_surveys.csv, got {len(lines)}'
    )
    for i, (actual, expected) in enumerate(zip(lines, expected_content)):
        assert actual == expected, (
            f"Line {i + 1} mismatch. Expected '{expected}', got '{actual}'"
        )

    # Preserve the original verifier's log assertions.
    assert os.path.exists(LOG), f'Log file {LOG} is missing.'
    assert os.path.isfile(LOG), f'{LOG} is not a file.'
    with open(LOG) as f:
        content = f.read()
    for message in (
        'Pipeline started',
        'Melted data: 15 rows',
        'Cleaned data: 9 rows',
        'Pipeline completed',
    ):
        assert message in content, f"Expected log message '{message}' not found in {LOG}"


def main():
    assert os.path.exists(SCRIPT), f'File {SCRIPT} is missing.'
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT} is not a regular file.'
    assert os.path.getsize(SCRIPT) > 0, f'{SCRIPT} is empty.'

    with open(SCRIPT, encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)
    imports_logging = any(
        (isinstance(node, ast.Import) and any(alias.name == 'logging' for alias in node.names))
        or isinstance(node, ast.ImportFrom) and node.module == 'logging'
        for node in ast.walk(tree)
    )
    assert imports_logging, 'process_feedback.py must use Python\'s logging module.'

    with open(RAW, 'rb') as f:
        original_raw = f.read()

    ids = random.sample(range(1000, 9000), 3)
    nonce = secrets.token_hex(6)
    rows = [
        {
            'user_id': ids[1], 'age': 31,
            'q1_response': f'  Alpha!!!   {nonce.upper()}?? ',
            'q2_response': '',
            'q3_response': f'Code-{nonce}',
        },
        {
            'user_id': ids[0], 'age': 42,
            'q1_response': None,
            'q2_response': ' MIXED_case, 42! ',
            'q3_response': 'Keep   These   Spaces',
        },
        {
            'user_id': ids[1], 'age': 99,
            'q1_response': 'duplicate must disappear',
            'q2_response': 'First valid q2.',
            'q3_response': 'duplicate must disappear',
        },
        {
            'user_id': ids[2], 'age': 27,
            'q1_response': "Customer's choice!",
            'q2_response': 'Symbols: #$% remain? No.',
            'q3_response': None,
        },
    ]
    expected = derive_expected(rows)

    try:
        pd.DataFrame(rows, columns=[
            'user_id', 'age', 'q1_response', 'q2_response', 'q3_response'
        ]).to_csv(RAW, index=False)
        run_pipeline()
        assert_dynamic_output(expected, len(rows) * 3)
    finally:
        with open(RAW, 'wb') as f:
            f.write(original_raw)

    # Execute the submitted artifact against the original input, then retain all
    # assertions made by the original verifier.
    run_pipeline()
    assert_original_output()


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
