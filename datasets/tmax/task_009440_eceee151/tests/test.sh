#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import shutil
import subprocess
import tempfile

SCRIPT_PATH = '/home/user/find_leak.sh'
REPORT_PATH = '/home/user/leak_report.txt'
TRAIN_DIR = '/home/user/artifacts/train'
TEST_DIR = '/home/user/artifacts/test'


def read_vector(filepath):
    with open(filepath, 'r') as f:
        return [float(line.strip()) for line in f if line.strip()]


def compute_closest_pair(train_dir, test_dir):
    test_files = [f for f in os.listdir(test_dir) if f.startswith('test_') and f.endswith('.txt')]
    train_files = [f for f in os.listdir(train_dir) if f.startswith('train_') and f.endswith('.txt')]

    closest_pair = None
    min_dist = float('inf')
    for test_f in test_files:
        test_vec = read_vector(os.path.join(test_dir, test_f))
        for train_f in train_files:
            train_vec = read_vector(os.path.join(train_dir, train_f))
            dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(test_vec, train_vec)))
            if dist < min_dist:
                min_dist = dist
                closest_pair = (test_f, train_f)
    return closest_pair, min_dist


def read_report():
    assert os.path.isfile(REPORT_PATH), f'Report file {REPORT_PATH} does not exist.'
    with open(REPORT_PATH, 'r') as f:
        content = f.read().strip()
    words = content.split()
    assert len(words) == 2, f'Expected exactly 2 words in {REPORT_PATH}, found {len(words)}: {content}'
    return words


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run([SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=30)
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} exited with status {result.returncode}. '
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )


def test_find_leak_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Script {SCRIPT_PATH} is not executable.'


def test_script_executes_and_leak_report_content():
    # Execute the submitted artifact rather than trusting a pre-created report.
    run_script()

    closest_pair, min_dist = compute_closest_pair(TRAIN_DIR, TEST_DIR)
    assert min_dist < 0.05, 'No pair found with L2 distance < 0.05 in the dataset.'

    words = read_report()
    assert words[0] == closest_pair[0], f'Expected test file {closest_pair[0]}, found {words[0]}'
    assert words[1] == closest_pair[1], f'Expected train file {closest_pair[1]}, found {words[1]}'


def test_script_finds_runtime_generated_pairs():
    # Swap in several datasets whose filenames and leaking pair are selected only
    # at verification time, preventing a hardcoded answer from passing.
    backup_root = tempfile.mkdtemp(prefix='leak-verifier-')
    backup_train = os.path.join(backup_root, 'train')
    backup_test = os.path.join(backup_root, 'test')
    saved_report = None
    if os.path.isfile(REPORT_PATH):
        with open(REPORT_PATH, 'rb') as f:
            saved_report = f.read()

    shutil.move(TRAIN_DIR, backup_train)
    shutil.move(TEST_DIR, backup_test)

    try:
        rng = random.SystemRandom()
        for trial in range(3):
            shutil.rmtree(TRAIN_DIR, ignore_errors=True)
            shutil.rmtree(TEST_DIR, ignore_errors=True)
            os.makedirs(TRAIN_DIR)
            os.makedirs(TEST_DIR)

            train_names = [f'train_{secrets.randbelow(900000) + 100000}.txt' for _ in range(6)]
            test_names = [f'test_{secrets.randbelow(900000) + 100000}.txt' for _ in range(5)]
            while len(set(train_names)) != len(train_names):
                train_names = [f'train_{secrets.randbelow(900000) + 100000}.txt' for _ in range(6)]
            while len(set(test_names)) != len(test_names):
                test_names = [f'test_{secrets.randbelow(900000) + 100000}.txt' for _ in range(5)]

            train_vectors = [[0.1 * (i + 1) + 0.002 * d for d in range(10)] for i in range(6)]
            test_vectors = [[2.0 + 0.2 * i + 0.003 * d for d in range(10)] for i in range(5)]
            leak_train = rng.randrange(len(train_names))
            leak_test = rng.randrange(len(test_names))
            test_vectors[leak_test] = [x + 0.001 for x in train_vectors[leak_train]]

            for name, vector in zip(train_names, train_vectors):
                with open(os.path.join(TRAIN_DIR, name), 'w') as f:
                    f.write(''.join(f'{value:.12f}\n' for value in vector))
            for name, vector in zip(test_names, test_vectors):
                with open(os.path.join(TEST_DIR, name), 'w') as f:
                    f.write(''.join(f'{value:.12f}\n' for value in vector))

            expected_pair, min_dist = compute_closest_pair(TRAIN_DIR, TEST_DIR)
            assert min_dist < 0.05
            run_script()
            words = read_report()
            assert tuple(words) == expected_pair, (
                f'On runtime dataset {trial + 1}, expected {expected_pair[0]} '
                f'{expected_pair[1]}, found {" ".join(words)}'
            )
    finally:
        shutil.rmtree(TRAIN_DIR, ignore_errors=True)
        shutil.rmtree(TEST_DIR, ignore_errors=True)
        shutil.move(backup_train, TRAIN_DIR)
        shutil.move(backup_test, TEST_DIR)
        shutil.rmtree(backup_root, ignore_errors=True)
        if saved_report is None:
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
        else:
            with open(REPORT_PATH, 'wb') as f:
                f.write(saved_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
