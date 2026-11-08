#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import stat
import subprocess
import pytest

PREPARE = '/home/user/prepare_dataset.sh'
VALIDATE = '/home/user/validate.sh'
DOCS = '/home/user/data/documents.csv'
TRAIN = '/home/user/data/train_normalized.csv'
TEST = '/home/user/data/test_normalized.csv'
RESULT = '/home/user/covariance_result.txt'


def run_script(path):
    completed = subprocess.run([path], text=True, capture_output=True, timeout=15)
    assert completed.returncode == 0, (
        f'{path} failed with exit code {completed.returncode}\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )


def load_source_rows():
    with open(DOCS, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines and lines[0] == 'id,text,label', 'documents.csv has an unexpected header'
    return lines[1:]


def expected_splits():
    data = load_source_rows()
    train_lines = len(data) * 80 // 100
    return data[:train_lines], data[train_lines:]


def check_normalized_file(path, expected_rows, max_words):
    with open(path, 'r') as f:
        actual_rows = [line.strip() for line in f if line.strip()]
    assert len(actual_rows) == len(expected_rows), f'{path} has an incorrect number of rows'

    for i, (source, actual) in enumerate(zip(expected_rows, actual_rows), 1):
        parts = source.split(',')
        assert len(parts) == 3
        doc_id, text, label = parts
        fields = actual.split()
        assert len(fields) == 3, f'{path} row {i} does not have exactly 3 space-separated columns'
        assert fields[0] == doc_id, f'{path} row {i} ID mismatch'
        assert fields[2] == label, f'{path} row {i} label mismatch'
        expected = len(text.split()) / max_words
        try:
            observed = float(fields[1])
        except ValueError:
            pytest.fail(f'{path} row {i} has a non-numeric normalized word count')
        assert math.isclose(observed, expected, rel_tol=1e-4, abs_tol=1e-8), (
            f'{path} row {i} has incorrect normalized word count. '
            f'Expected {expected}, got {observed}'
        )


def covariance_from_file(path):
    xs, ys = [], []
    with open(path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.split()
            assert len(parts) == 3
            xs.append(float(parts[1]))
            ys.append(float(parts[2]))
    assert xs, f'{path} is empty'
    n = len(xs)
    return sum(x * y for x, y in zip(xs, ys)) / n - (sum(xs) / n) * (sum(ys) / n)


def read_result():
    assert os.path.isfile(RESULT), f'{RESULT} is missing. Did you run validate.sh?'
    with open(RESULT, 'r') as f:
        content = f.read().strip()
    try:
        return float(content)
    except ValueError:
        pytest.fail(f'Content of {RESULT} is not a valid number: {content}')


def test_00_scripts_exist_are_executable_and_run():
    for path in (PREPARE, VALIDATE):
        assert os.path.isfile(path), f'{path} is missing'
        st = os.stat(path)
        assert bool(st.st_mode & stat.S_IXUSR), f'{path} is not executable'
    run_script(PREPARE)
    run_script(VALIDATE)


def test_normalized_files_exist():
    assert os.path.isfile(TRAIN), '/home/user/data/train_normalized.csv is missing'
    assert os.path.isfile(TEST), '/home/user/data/test_normalized.csv is missing'


def test_normalization_logic():
    # Read the original documents to compute truth dynamically.
    train_data, test_data = expected_splits()
    max_words_train = max(len(row.split(',')[1].split()) for row in train_data)
    assert max_words_train > 0, 'Could not compute max words from training data'

    # Preserve the original test-set assertion and also validate the training output.
    check_normalized_file(TEST, test_data, max_words_train)
    check_normalized_file(TRAIN, train_data, max_words_train)


def test_validate_script_exists_and_executable():
    script_path = VALIDATE
    assert os.path.isfile(script_path), f'{script_path} is missing'
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'{script_path} is not executable'


def test_validate_script_uses_awk_and_required_input():
    with open(VALIDATE, 'r') as f:
        source_lines = f.readlines()
    active = '\n'.join(line.split('#', 1)[0] for line in source_lines)
    assert '/home/user/data/test_normalized.csv' in active, (
        'validate.sh must read /home/user/data/test_normalized.csv'
    )
    assert re.search(r'(^|[^A-Za-z0-9_])(?:g?awk|/[^\s;|&()]*awk)(?=\s)', active, re.M), (
        'validate.sh must use awk to calculate covariance'
    )


def test_covariance_result():
    expected_cov = covariance_from_file(TEST)
    actual_cov = read_result()
    assert math.isclose(actual_cov, expected_cov, abs_tol=1e-4), (
        f'Covariance in {RESULT} ({actual_cov}) does not match expected '
        f'population covariance ({expected_cov:.4f})'
    )


def test_pipeline_on_unseen_data_and_validate_reads_test_file():
    with open(DOCS, 'rb') as f:
        original_docs = f.read()

    try:
        # Generate an unseen dataset with a test-only maximum, so fitting before
        # splitting produces observably wrong train and test normalization.
        train_count = 10
        test_count = 3
        train_word_counts = [1 + secrets.randbelow(12) for _ in range(train_count)]
        train_max = max(train_word_counts)
        test_word_counts = [1 + secrets.randbelow(8), 1 + secrets.randbelow(8), train_max + 5 + secrets.randbelow(8)]
        counts = train_word_counts + test_word_counts
        id_base = 10000 + secrets.randbelow(800000)
        flip = secrets.randbelow(2)

        rows = []
        for i, count in enumerate(counts):
            words = [secrets.token_hex(4) for _ in range(count)]
            rows.append(f'{id_base + i},{" ".join(words)},{(i + flip) % 2}')

        with open(DOCS, 'w') as f:
            f.write('id,text,label\n' + '\n'.join(rows) + '\n')

        run_script(PREPARE)
        dynamic_train, dynamic_test = expected_splits()
        dynamic_max = max(len(row.split(',')[1].split()) for row in dynamic_train)
        check_normalized_file(TRAIN, dynamic_train, dynamic_max)
        check_normalized_file(TEST, dynamic_test, dynamic_max)

        # Independently replace the required input with unpredictable values.
        # This ensures validate.sh actually reads that file rather than deriving
        # or hard-coding the result from documents.csv.
        probe_rows = []
        for i in range(5):
            x = (1 + secrets.randbelow(9000)) / 997.0
            y = ((i + flip) % 3) - 1
            probe_rows.append(f'{id_base + 100 + i} {x:.10f} {y}')
        with open(TEST, 'w') as f:
            f.write('\n'.join(probe_rows) + '\n')
        if os.path.exists(RESULT):
            os.remove(RESULT)

        expected_probe_cov = covariance_from_file(TEST)
        run_script(VALIDATE)
        actual_probe_cov = read_result()
        assert math.isclose(actual_probe_cov, expected_probe_cov, abs_tol=1e-4), (
            'validate.sh did not compute population covariance from the current '
            '/home/user/data/test_normalized.csv contents'
        )
    finally:
        with open(DOCS, 'wb') as f:
            f.write(original_docs)
        # Restore the required final artifacts for the original dataset.
        run_script(PREPARE)
        run_script(VALIDATE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
