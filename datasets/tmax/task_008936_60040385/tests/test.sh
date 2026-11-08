#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import datetime
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile
import unicodedata

OUTPUT = Path('/home/user/changepoints.json')
REVIEWS = Path('/home/user/reviews')
ENCODINGS = ['utf-8', 'iso-8859-1', 'shift_jis', 'utf-16', 'cp1251']
FILLERS = ['x', 'é', 'あ', '界', 'Ж']
USERNAMES = ['user', 'utilisateuré', '利用者', '用戶', 'Пользователь']


def test_changepoints_json_exists():
    """Test that the changepoints.json file exists."""
    file_path = "/home/user/changepoints.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. The task requires creating this file."


def test_changepoints_json_content():
    """Test that the changepoints.json contains the correct dates."""
    file_path = "/home/user/changepoints.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} does not contain valid JSON."

    expected = ["2023-10-04", "2023-10-08"]
    assert isinstance(data, list), "The JSON content should be a list of strings."
    assert data == expected, f"Expected changepoints {expected}, but got {data}."


def has_parallel_processing(path):
    try:
        tree = ast.parse(path.read_text(encoding='utf-8'))
    except (OSError, UnicodeDecodeError, SyntaxError):
        return False

    imported = False
    constructs = set()
    operations = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing' or alias.name.startswith('concurrent.futures'):
                    imported = True
        elif isinstance(node, ast.ImportFrom):
            if node.module == 'multiprocessing' or (node.module and node.module.startswith('concurrent.futures')):
                imported = True
        elif isinstance(node, ast.Call):
            fn = node.func
            if isinstance(fn, ast.Name):
                name = fn.id
            elif isinstance(fn, ast.Attribute):
                name = fn.attr
            else:
                continue
            if name in {'ThreadPoolExecutor', 'ProcessPoolExecutor', 'Executor', 'Pool', 'Process'}:
                constructs.add(name)
            if name in {'map', 'starmap', 'imap', 'imap_unordered', 'submit', 'start'}:
                operations.add(name)
    return imported and bool(constructs) and bool(operations)


def expected_for(rows_by_file):
    lengths = {}
    for rows in rows_by_file:
        for date, _username, review in rows:
            lengths.setdefault(date, []).append(len(unicodedata.normalize('NFKC', review)))
    dates = sorted(lengths)
    averages = {date: sum(lengths[date]) / len(lengths[date]) for date in dates}
    return [dates[i] for i in range(1, len(dates))
            if averages[dates[i]] > 2.0 * averages[dates[i - 1]]]


def write_dataset(rows_by_file):
    if REVIEWS.exists():
        shutil.rmtree(REVIEWS)
    REVIEWS.mkdir(parents=True)
    for i, encoding in enumerate(ENCODINGS):
        path = REVIEWS / f'data_{i + 1}.csv'
        with path.open('w', encoding=encoding, newline='') as handle:
            writer = csv.writer(handle)
            writer.writerow(['Date', 'Username', 'Review_Text'])
            writer.writerows(rows_by_file[i])


def normalization_dataset(start):
    dates = [(start + datetime.timedelta(days=i)).isoformat() for i in range(7)]
    rows = [[] for _ in range(5)]
    # NFKC expands each ligature from one code point to three. Without
    # normalization, the second date is incorrectly classified as a jump.
    rows[0].append((dates[0], USERNAMES[0], 'ﬃﬃ'))
    rows[0].append((dates[0], USERNAMES[0], 'ﬃﬃ'))
    specifications = [
        ((4, 6), (1, 2)),
        ((10, 10), (3, 4)),
        ((2, 4), (1, 2)),
        ((6, 8), (3, 4)),
        ((2, 2), (1, 2)),
        ((4, 6), (3, 4)),
    ]
    for date, (lengths, files) in zip(dates[1:], specifications):
        for length, file_index in zip(lengths, files):
            rows[file_index].append((date, USERNAMES[file_index], FILLERS[file_index] * length))
    return rows


def randomized_dataset(rng, start):
    rows = [[] for _ in range(5)]
    dates = [(start + datetime.timedelta(days=i)).isoformat() for i in range(9)]
    lengths = [rng.randint(2, 18) for _ in dates]
    # Ensure the trial contains both a strict jump and an exact 2x boundary.
    lengths[3] = rng.randint(2, 7)
    lengths[4] = lengths[3] * 2
    lengths[5] = rng.randint(2, 6)
    lengths[6] = lengths[5] * 2 + 1
    for i, (date, average) in enumerate(zip(dates, lengths)):
        pair = (average - 1, average + 1) if average > 1 else (average, average)
        for j, length in enumerate(pair):
            file_index = (2 * i + j) % 5
            rows[file_index].append(
                (date, USERNAMES[file_index], FILLERS[file_index] * length)
            )
    return rows


def execute_and_read(script):
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        ['python3', str(script)], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f'{script} exited with status {result.returncode}: {result.stderr[-2000:]}'
    )
    assert OUTPUT.is_file(), f'{script} did not create {OUTPUT}'
    try:
        with OUTPUT.open('r', encoding='utf-8') as handle:
            value = json.load(handle)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AssertionError(f'{script} produced invalid UTF-8 JSON: {exc}')
    assert isinstance(value, list) and all(isinstance(item, str) for item in value), \
        'The generated JSON must be an array of strings.'
    return value


def test_python_pipeline_executes_and_generalizes():
    scripts = [
        path for path in Path('/home/user').rglob('*.py')
        if path.is_file() and '__pycache__' not in path.parts
    ]
    parallel_scripts = [path for path in scripts if has_parallel_processing(path)]
    assert parallel_scripts, (
        'No Python script using concurrent.futures or multiprocessing for parallel work was found.'
    )

    rng = random.SystemRandom()
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        original_reviews = Path(tmp) / 'reviews'
        shutil.copytree(REVIEWS, original_reviews)

        def restore_original():
            if REVIEWS.exists():
                shutil.rmtree(REVIEWS)
            shutil.copytree(original_reviews, REVIEWS)

        try:
            for script in parallel_scripts:
                try:
                    restore_original()
                    assert execute_and_read(script) == ['2023-10-04', '2023-10-08'], \
                        f'{script} did not compute the original dataset correctly.'

                    start = datetime.date(2024, 1, 1) + datetime.timedelta(days=rng.randrange(0, 300))
                    rows = normalization_dataset(start)
                    write_dataset(rows)
                    assert execute_and_read(script) == expected_for(rows), \
                        f'{script} failed mixed-encoding/NFKC/aggregation testing.'

                    for _ in range(2):
                        start = datetime.date(2025, 1, 1) + datetime.timedelta(days=rng.randrange(0, 300))
                        rows = randomized_dataset(rng, start)
                        write_dataset(rows)
                        assert execute_and_read(script) == expected_for(rows), \
                            f'{script} failed changepoint testing on generated input.'
                    return
                except (AssertionError, subprocess.TimeoutExpired, OSError) as exc:
                    failures.append(f'{script}: {exc}')
        finally:
            restore_original()

    raise AssertionError('No submitted Python pipeline passed execution tests. ' + ' | '.join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
