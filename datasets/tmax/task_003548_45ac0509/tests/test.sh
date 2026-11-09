#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import stat
import subprocess
import tempfile

RAW_PATH = '/home/user/raw_data.csv'
OUTPUT_PATH = '/home/user/processed_embeddings.csv'
CPP_PATH = '/home/user/prepare.cpp'
EXE_PATH = '/home/user/prepare'


def expected_lines(raw_path):
    expected = []
    with open(raw_path, 'r') as infile:
        for L, line in enumerate(infile):
            if (L * 9973) % 100000 < 1000:
                x = [float(val) for val in line.strip().split(',')]
                assert len(x) == 10, f'Row {L} does not contain 10 values.'
                e0, e1, e2 = 0.0, 0.0, 0.0
                for j in range(10):
                    weight = j + 1
                    e0 += x[j] * weight
                    e1 += x[j] * (weight ** 2)
                    e2 += x[j] * (weight ** 3)
                expected.append(f'{e0:.4f},{e1:.4f},{e2:.4f}\n')
    return expected


def assert_output_matches(raw_path, output_path):
    expected = expected_lines(raw_path)
    assert os.path.isfile(output_path), f'Output file {output_path} is missing.'
    with open(output_path, 'r') as outfile:
        actual = outfile.readlines()

    assert len(actual) == len(expected), \
        f'Expected {len(expected)} lines in {output_path}, but found {len(actual)}.'
    for i, (wanted, got) in enumerate(zip(expected, actual)):
        assert got.strip() == wanted.strip(), \
            f'Mismatch at line {i + 1} in {output_path}.\nExpected: {wanted.strip()}\nActual: {got.strip()}'


def run_compiled_program():
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    subprocess.run([EXE_PATH], cwd='/home/user', check=True, timeout=120)
    assert os.path.isfile(OUTPUT_PATH), \
        f'Running {EXE_PATH} did not create {OUTPUT_PATH}.'


def test_cpp_program_and_processed_embeddings():
    # Preserve the original checks on the supplied files and final output.
    assert os.path.isfile(RAW_PATH), f'Raw data file {RAW_PATH} is missing.'
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} is missing.'
    assert_output_matches(RAW_PATH, OUTPUT_PATH)
    assert os.path.isfile(CPP_PATH), f'C++ source file {CPP_PATH} is missing.'

    # The submitted source must actually compile as the requested C++ program.
    subprocess.run(
        ['g++', '-O3', CPP_PATH, '-o', EXE_PATH],
        check=True,
        timeout=120,
    )
    assert os.path.isfile(EXE_PATH), f'Compilation did not create {EXE_PATH}.'

    original_mode = stat.S_IMODE(os.stat(RAW_PATH).st_mode)
    fd, backup_path = tempfile.mkstemp(prefix='raw_data_backup_', suffix='.csv')
    os.close(fd)
    shutil.copyfile(RAW_PATH, backup_path)

    dynamic_error = None
    try:
        # Exercise the compiled artifact on fresh data unavailable to the agent.
        rng = random.Random(secrets.randbits(256))
        with open(RAW_PATH, 'w') as dynamic_raw:
            for _ in range(100000):
                dynamic_raw.write(','.join(str(rng.randint(-100, 100)) for _ in range(10)) + '\n')

        try:
            run_compiled_program()
            assert_output_matches(RAW_PATH, OUTPUT_PATH)
        except BaseException as exc:
            dynamic_error = exc
    finally:
        shutil.copyfile(backup_path, RAW_PATH)
        os.chmod(RAW_PATH, original_mode)
        os.remove(backup_path)

    # Execute the compiled program again on the real input, leaving the required
    # final artifact in place and checking all original output assertions again.
    run_compiled_program()
    assert_output_matches(RAW_PATH, OUTPUT_PATH)

    if dynamic_error is not None:
        raise dynamic_error
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
