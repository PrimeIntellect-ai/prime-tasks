#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess

import pytest

PIPELINE_DIR = '/home/user/pipeline'
SOURCE_A = '/home/user/data/sourceA.csv'
SOURCE_B = '/home/user/data/sourceB.csv'
OUTPUT_FILE = '/home/user/output/training_data.csv'


def test_pipeline_compilation_and_execution():
    """Test that the Makefile compiles the C program and generates the output."""
    pipeline_dir = '/home/user/pipeline'

    assert os.path.isfile(os.path.join(pipeline_dir, 'Makefile')), "Makefile is missing in /home/user/pipeline."
    assert os.path.isfile(os.path.join(pipeline_dir, 'process.c')), "process.c is missing in /home/user/pipeline."

    # Run make
    result = subprocess.run(['make', '-C', pipeline_dir, 'all'], capture_output=True, text=True)
    assert result.returncode == 0, f"make failed with error:\n{result.stderr}\n{result.stdout}"

    # Verify executable exists
    assert os.path.isfile(os.path.join(pipeline_dir, 'process')), "Executable 'process' was not created by make."


def test_training_data_output():
    """Test that the output CSV matches the expected dimensionality reduction results."""
    output_file = '/home/user/output/training_data.csv'

    assert os.path.isfile(output_file), f"Output file {output_file} is missing. Make sure the C program generates it."

    expected_csv = "id,PC1,PC2\n2,72.0,10.0\n3,82.0,10.0\n5,30.0,10.0\n"

    with open(output_file, 'r') as f:
        content = f.read()

    # Normalize line endings and strip trailing whitespace
    actual_lines = [line.strip() for line in content.strip().splitlines()]
    expected_lines = [line.strip() for line in expected_csv.strip().splitlines()]

    assert actual_lines == expected_lines, (
        f"Content of {output_file} does not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def write_random_fixture(rng):
    ids = rng.sample(range(100, 10000), 9)
    common = ids[:5]
    a_ids = common + ids[5:7]
    b_ids = common + ids[7:9]

    a_rows = {}
    b_rows = {}
    for record_id in a_ids:
        a_rows[record_id] = [rng.randint(-50, 100) for _ in range(3)]
    for record_id in b_ids:
        b_rows[record_id] = [rng.randint(-50, 100) for _ in range(2)]

    rng.shuffle(a_ids)
    rng.shuffle(b_ids)

    with open(SOURCE_A, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'f1', 'f2', 'f3'])
        for record_id in a_ids:
            writer.writerow([record_id] + a_rows[record_id])

    with open(SOURCE_B, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'f4', 'f5'])
        for record_id in b_ids:
            writer.writerow([record_id] + b_rows[record_id])

    expected = ['id,PC1,PC2']
    for record_id in sorted(common):
        f1, f2, f3 = a_rows[record_id]
        f4, f5 = b_rows[record_id]
        pc1 = 0.2 * f1 + 0.4 * f2 + 0.4 * f3 + 0.5 * f4 + 0.5 * f5
        pc2 = -0.5 * f1 + 0.5 * f2 + 0.0 * f3 - 0.5 * f4 + 0.5 * f5
        expected.append(f'{record_id},{pc1:.1f},{pc2:.1f}')
    return expected


def assert_output(expected_lines):
    assert os.path.isfile(OUTPUT_FILE), 'The process did not create training_data.csv.'
    with open(OUTPUT_FILE, 'r') as f:
        actual_lines = [line.strip() for line in f.read().strip().splitlines()]
    assert actual_lines == expected_lines, (
        'Output was incorrect for verifier-generated CSV inputs.\n'
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_process_c_and_makefile_on_generated_inputs():
    """Compile process.c directly and exercise both it and the Makefile on fresh inputs."""
    source = os.path.join(PIPELINE_DIR, 'process.c')
    verifier_binary = '/tmp/verifier_process'

    compile_result = subprocess.run(
        ['gcc', '-O3', source, '-o', verifier_binary, '-lm'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        'process.c did not compile with gcc -O3.\n'
        f'{compile_result.stdout}\n{compile_result.stderr}'
    )
    assert open(verifier_binary, 'rb').read(4) == b'\x7fELF', 'Compiled process.c is not a native executable.'

    rng = random.SystemRandom()
    for _ in range(2):
        expected = write_random_fixture(rng)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        result = subprocess.run(
            [verifier_binary], cwd=PIPELINE_DIR, capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, (
            f'Directly compiled process.c failed.\n{result.stdout}\n{result.stderr}'
        )
        assert_output(expected)

    expected = write_random_fixture(rng)
    process_path = os.path.join(PIPELINE_DIR, 'process')
    if os.path.exists(process_path):
        os.remove(process_path)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run(
        ['make', '-B', '-C', PIPELINE_DIR, 'all'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"make failed on generated inputs:\n{result.stderr}\n{result.stdout}"
    assert os.path.isfile(process_path), "Executable 'process' was not created by make."
    assert os.access(process_path, os.X_OK), "The generated 'process' file is not executable."
    with open(process_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Makefile did not produce a native compiled executable."
    assert_output(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
