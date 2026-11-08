#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import shutil
import subprocess
from collections import Counter
from pathlib import Path

import pytest

PROJECT = Path('/home/user/text_analyzer')
DATASET = Path('/home/user/dataset.csv')
RESULTS = Path('/home/user/tuning_results.json')


def expected_embedding(text):
    vowels = set('aeiouAEIOU')
    return [
        float(len(text)),
        float(sum(c in vowels for c in text)),
        float(sum(c.isalpha() and c not in vowels for c in text)),
        float(sum(c.isspace() for c in text)),
        float(sum(ord(c) for c in text) % 100),
    ]


def expected_result(path):
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            try:
                int(row.get('id', ''))
            except (ValueError, TypeError):
                continue
            text = row.get('text', '')
            label = row.get('label', '')
            if text == '' or not label:
                continue
            rows.append((expected_embedding(text), label))

    n = len(rows)
    base = n // 5
    folds = []
    start = 0
    for i in range(5):
        size = base if i < 4 else n - start
        folds.append(rows[start:start + size])
        start += size

    accuracies = {}
    for k in (1, 3, 5):
        correct = total = 0
        for i, validation in enumerate(folds):
            training = [item for j, fold in enumerate(folds) if j != i for item in fold]
            assert len(training) >= k
            for vector, true_label in validation:
                distances = []
                for order, (other, label) in enumerate(training):
                    squared = sum((a - b) ** 2 for a, b in zip(vector, other))
                    distances.append((squared, order, label))
                distances.sort(key=lambda item: (item[0], item[1]))
                counts = Counter(label for _, _, label in distances[:k])
                largest = max(counts.values())
                predicted = min(label for label, count in counts.items() if count == largest)
                correct += predicted == true_label
                total += 1
        accuracies[k] = correct / total
    best_accuracy = max(accuracies.values())
    best_k = min(k for k, accuracy in accuracies.items() if accuracy == best_accuracy)
    return best_k, best_accuracy


def read_results():
    assert RESULTS.is_file(), f'Output file {RESULTS} does not exist.'
    with open(RESULTS, encoding='utf-8') as f:
        result = json.load(f)
    assert 'best_k' in result, "Missing 'best_k' in tuning_results.json"
    assert 'best_accuracy' in result, "Missing 'best_accuracy' in tuning_results.json"
    return result


def assert_result(expected):
    result = read_results()
    assert type(result['best_k']) is int
    assert result['best_k'] == expected[0]
    assert isinstance(result['best_accuracy'], (int, float)) and not isinstance(result['best_accuracy'], bool)
    assert math.isfinite(result['best_accuracy'])
    assert abs(result['best_accuracy'] - expected[1]) < 1e-5


def run_binary():
    completed = subprocess.run(
        [str(PROJECT / 'target/release/text_analyzer')],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr


def write_dataset(rows):
    with open(DATASET, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'text', 'label'])
        writer.writerows(rows)


def test_project_builds_and_runs_on_original_dataset():
    assert (PROJECT / 'Cargo.toml').is_file()
    assert (PROJECT / 'src/embedding.rs').is_file()
    assert (PROJECT / 'src/main.rs').is_file()
    completed = subprocess.run(
        ['cargo', 'build', '--release'], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    expected = expected_result(DATASET)
    RESULTS.unlink(missing_ok=True)
    run_binary()
    assert_result(expected)


def test_embedding_function_directly(tmp_path):
    source = PROJECT / 'src/embedding.rs'
    harness = tmp_path / 'embedding_harness.rs'
    executable = tmp_path / 'embedding_harness'
    harness.write_text(
        '#[path = ' + json.dumps(str(source)) + '] mod embedding;\n'
        'fn main() {\n'
        '  for s in ["", "Ae i!", "Rust\\tLang", "xyz 123", "café"] {\n'
        '    println!("{:?}", embedding::embed(s));\n'
        '  }\n'
        '}\n', encoding='utf-8'
    )
    compiled = subprocess.run(
        ['rustc', '--edition=2021', str(harness), '-o', str(executable)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    output = subprocess.run(
        [str(executable)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10, check=True
    ).stdout.splitlines()
    actual = [json.loads(line) for line in output]
    samples = ['', 'Ae i!', 'Rust\tLang', 'xyz 123', 'café']
    assert actual == [expected_embedding(sample) for sample in samples]


def test_pipeline_on_unseen_dataset():
    # Twenty-five valid rows exercise sequential folds of five; malformed rows
    # ensure schema filtering is performed by the submitted executable.
    valid = [
        (101, 'aa', 'Z'), (102, 'bbbb', 'A'), (103, 'c c', 'M'),
        (104, 'Echo!', 'A'), (105, 'uuuuu', 'Z'), (106, 'stone', 'M'),
        (107, 'tiny', 'A'), (108, 'LONG phrase', 'Z'), (109, 'q', 'M'),
        (110, 'a e i', 'A'), (111, 'rhythm', 'Z'), (112, 'book', 'M'),
        (113, 'sky blue', 'A'), (114, 'delta', 'Z'), (115, 'NNN', 'M'),
        (116, 'ice', 'A'), (117, 'two  spaces', 'Z'), (118, 'rustacean', 'M'),
        (119, 'O', 'A'), (120, 'abcdef', 'Z'), (121, 'zzz top', 'M'),
        (122, 'lima', 'A'), (123, 'queue', 'Z'), (124, 'pqr', 'M'),
        (125, 'final row', 'A'),
    ]
    rows = valid[:7] + [('not-an-int', 'oracle bait', 'Q'), (999, '', 'Q'), (1000, 'missing label', '')] + valid[7:]
    write_dataset(rows)
    expected = expected_result(DATASET)
    RESULTS.unlink(missing_ok=True)
    run_binary()
    assert_result(expected)


@pytest.fixture(scope='module', autouse=True)
def restore_files():
    original_dataset = DATASET.read_bytes()
    original_results = RESULTS.read_bytes() if RESULTS.exists() else None
    yield
    DATASET.write_bytes(original_dataset)
    if original_results is None:
        RESULTS.unlink(missing_ok=True)
    else:
        RESULTS.write_bytes(original_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
