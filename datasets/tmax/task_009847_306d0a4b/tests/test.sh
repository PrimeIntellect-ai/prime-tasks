#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
from collections import Counter

C_FILE = '/home/user/find_similar.c'
CSV_FILE = '/home/user/math_texts.csv'
RESULT_FILE = '/home/user/result.txt'
BINARY = '/tmp/find_similar_test'


def get_vector(text):
    counts = Counter(c.lower() for c in text if c.isalpha())
    return [counts[chr(ord('a') + i)] for i in range(26)]


def dot_product(v1, v2):
    return sum(x * y for x, y in zip(v1, v2))


def compute_expected_result(csv_path):
    data = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append((int(row['id']), get_vector(row['text'])))

    best_pair = None
    max_dot = -1
    for i in range(len(data)):
        for j in range(i + 1, len(data)):
            id1, v1 = data[i]
            id2, v2 = data[j]
            if id1 > id2:
                id1, id2 = id2, id1
            dp = dot_product(v1, v2)
            if dp > max_dot:
                max_dot = dp
                best_pair = (id1, id2)
            elif dp == max_dot:
                if id1 < best_pair[0] or (id1 == best_pair[0] and id2 < best_pair[1]):
                    best_pair = (id1, id2)

    return f"{best_pair[0]},{best_pair[1]},{max_dot}"


def run_program_and_check():
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)
    proc = subprocess.run([BINARY], cwd='/home/user', capture_output=True, text=True, timeout=10)
    assert proc.returncode == 0, f"Program exited with status {proc.returncode}: {proc.stderr}"
    assert os.path.exists(RESULT_FILE), f"Program did not create {RESULT_FILE}."
    assert os.path.isfile(RESULT_FILE), f"{RESULT_FILE} is not a file."
    expected = compute_expected_result(CSV_FILE)
    with open(RESULT_FILE, 'r', encoding='utf-8') as f:
        actual = f.read().strip()
    assert actual == expected, f"Expected '{expected}' in {RESULT_FILE}, but got '{actual}'."


def write_dataset(rows):
    with open(CSV_FILE, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['id', 'text'])
        writer.writerows(rows)


def test_c_source_file_exists():
    assert os.path.exists(C_FILE), f"C source file {C_FILE} is missing."
    assert os.path.isfile(C_FILE), f"{C_FILE} is not a file."


def test_result_file_correctness():
    assert os.path.exists(CSV_FILE), f"Input CSV {CSV_FILE} is missing."
    assert os.path.exists(RESULT_FILE), f"Output file {RESULT_FILE} is missing."
    assert os.path.isfile(RESULT_FILE), f"{RESULT_FILE} is not a file."
    expected_result = compute_expected_result(CSV_FILE)
    with open(RESULT_FILE, 'r', encoding='utf-8') as f:
        actual_result = f.read().strip()
    assert actual_result == expected_result, f"Expected '{expected_result}' in {RESULT_FILE}, but got '{actual_result}'."


def test_c_program_compiles_and_processes_inputs():
    compile_proc = subprocess.run(
        ['gcc', '-std=c11', '-O2', C_FILE, '-o', BINARY],
        capture_output=True, text=True, timeout=20
    )
    assert compile_proc.returncode == 0, f"C source failed to compile: {compile_proc.stderr}"
    assert os.path.isfile(BINARY), "Compilation did not produce an executable."

    with open(CSV_FILE, 'rb') as f:
        original_csv = f.read()

    try:
        run_program_and_check()

        write_dataset([
            (10, 'Ab c!'),
            (3, 'aabb'),
            (7, 'BC? 123'),
            (21, 'z'),
        ])
        run_program_and_check()

        write_dataset([
            (9, 'a'),
            (2, 'b'),
            (5, 'c'),
        ])
        run_program_and_check()

        write_dataset([
            (42, 'Alpha, beta! ALPHA'),
            (11, 'beta alpha'),
            (30, 'zzzz numbers 123'),
            (4, 'Nothing but punctuation?!'),
        ])
        run_program_and_check()
    finally:
        with open(CSV_FILE, 'wb') as f:
            f.write(original_csv)
        if os.path.isfile(BINARY):
            if os.path.exists(RESULT_FILE):
                os.remove(RESULT_FILE)
            subprocess.run([BINARY], cwd='/home/user', capture_output=True, timeout=10)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
