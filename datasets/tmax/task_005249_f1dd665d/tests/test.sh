#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import random
import re
import stat
import subprocess
from pathlib import Path

DATASET = Path('/home/user/dataset.csv')
SOURCE = Path('/home/user/train.c')
EXECUTABLE = Path('/home/user/train')
ARTIFACT = Path('/home/user/artifact.json')


def compute_expected_results(dataset_path):
    rows = []
    f1_sum = 0.0
    f1_count = 0
    with open(dataset_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            f1_str = row['f1'].strip()
            if f1_str != 'NA':
                f1_val = float(f1_str)
                f1_sum += f1_val
                f1_count += 1
            rows.append(row)

    f1_mean = f1_sum / f1_count if f1_count > 0 else 0.0
    cleaned_rows = []
    for row in rows:
        f1_str = row['f1'].strip()
        f1_val = float(f1_str) if f1_str != 'NA' else f1_mean
        text = row['text'].strip()
        f2_val = len([w for w in text.split(' ') if w]) if text else 0
        if f2_val > 20:
            continue
        cleaned_rows.append((f1_val, f2_val, int(row['label'])))

    fold_A = [cleaned_rows[i] for i in range(len(cleaned_rows)) if i % 2 == 0]
    fold_B = [cleaned_rows[i] for i in range(len(cleaned_rows)) if i % 2 != 0]
    best_w1 = -999
    best_w2 = -999
    best_cv = -1.0

    for w1 in range(-10, 11):
        for w2 in range(-10, 11):
            correct_A = sum((1 if w1 * f1 + w2 * f2 > 0 else 0) == label
                            for f1, f2, label in fold_A)
            correct_B = sum((1 if w1 * f1 + w2 * f2 > 0 else 0) == label
                            for f1, f2, label in fold_B)
            accA = correct_A / len(fold_A) if fold_A else 0.0
            accB = correct_B / len(fold_B) if fold_B else 0.0
            cv_score = (accA + accB) / 2.0

            if cv_score > best_cv:
                best_cv, best_w1, best_w2 = cv_score, w1, w2
            elif abs(cv_score - best_cv) < 1e-9:
                if w1 > best_w1 or (w1 == best_w1 and w2 > best_w2):
                    best_w1, best_w2 = w1, w2

    return best_w1, best_w2, best_cv


def check_artifact():
    assert ARTIFACT.exists(), f'The artifact file {ARTIFACT} is missing.'
    assert ARTIFACT.is_file(), f'{ARTIFACT} is not a file.'

    raw = ARTIFACT.read_text().strip()
    pattern = r'[{]"best_w1": (-?[0-9]+), "best_w2": (-?[0-9]+), "cv_score": (-?[0-9]+[.][0-9]{4})[}]'
    assert re.fullmatch(pattern, raw), (
        'artifact.json must exactly use the required field order and spacing, '
        'with cv_score written as a JSON number having exactly four decimal places.'
    )

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{ARTIFACT} is not valid JSON: {exc}')

    assert 'best_w1' in data, "Missing 'best_w1' in artifact.json"
    assert 'best_w2' in data, "Missing 'best_w2' in artifact.json"
    assert 'cv_score' in data, "Missing 'cv_score' in artifact.json"

    expected_w1, expected_w2, expected_cv = compute_expected_results(DATASET)
    actual_w1 = int(data['best_w1'])
    actual_w2 = int(data['best_w2'])
    actual_cv = float(data['cv_score'])
    assert actual_w1 == expected_w1, f'Expected best_w1 to be {expected_w1}, but got {actual_w1}.'
    assert actual_w2 == expected_w2, f'Expected best_w2 to be {expected_w2}, but got {actual_w2}.'
    assert abs(actual_cv - expected_cv) < 1e-4, (
        f'Expected cv_score to be {expected_cv:.4f}, but got {actual_cv:.4f}.'
    )


def run_and_check():
    if ARTIFACT.exists() or ARTIFACT.is_symlink():
        ARTIFACT.unlink()
    subprocess.run([str(EXECUTABLE)], cwd='/home/user', check=True, timeout=10)
    check_artifact()


def make_dataset(row_count, rng):
    output = io.StringIO(newline='')
    writer = csv.writer(output)
    writer.writerow(['id', 'f1', 'text', 'label'])
    for i in range(row_count):
        missing = (i % 9 == 2) or rng.random() < 0.08
        f1_number = round(rng.uniform(-8.0, 8.0), 2)
        f1 = 'NA' if missing else f'{f1_number:.2f}'
        words = rng.randint(1, 25)
        text = ' '.join(['word'] * words)
        basis = 0.0 if missing else f1_number
        label = 1 if (rng.randint(-5, 5) * basis - rng.randint(-3, 3) * words) > 0 else 0
        if rng.random() < 0.15:
            label = 1 - label
        writer.writerow([i, f1, text, label])
    return output.getvalue().encode()


def test_c_pipeline_and_artifact():
    assert SOURCE.exists(), f'The required C source file {SOURCE} is missing.'
    assert stat.S_ISREGULAR(SOURCE.stat().st_mode), f'{SOURCE} is not a regular file.'

    original_dataset = DATASET.read_bytes()
    compiled = False
    if EXECUTABLE.exists() or EXECUTABLE.is_symlink():
        EXECUTABLE.unlink()

    try:
        subprocess.run(
            ['gcc', str(SOURCE), '-o', str(EXECUTABLE), '-lm'],
            cwd='/home/user', check=True, timeout=20
        )
        compiled = True
        assert EXECUTABLE.is_file(), 'gcc did not produce /home/user/train.'

        # Preserve the original result checks, but only after a fresh compiled run.
        run_and_check()

        # Exercise the same required pipeline on unknown datasets so a fixed artifact
        # or hardcoded values cannot satisfy the task.
        rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
        for count in (31, 47, 64):
            DATASET.write_bytes(make_dataset(count, rng))
            run_and_check()
    finally:
        DATASET.write_bytes(original_dataset)
        if compiled:
            try:
                if ARTIFACT.exists() or ARTIFACT.is_symlink():
                    ARTIFACT.unlink()
                subprocess.run([str(EXECUTABLE)], cwd='/home/user', timeout=10, check=False)
            except Exception:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
