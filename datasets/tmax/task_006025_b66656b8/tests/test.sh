#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import pytest


def generate_golden_output():
    input_path = '/home/user/raw_data.txt'
    if not os.path.exists(input_path):
        return None

    with open(input_path, 'r') as f:
        data = [float(line.strip()) for line in f if line.strip()]

    if not data:
        return []

    N = len(data)
    min_val = min(data)
    max_val = max(data)

    tokens = []
    for x in data:
        if x == max_val:
            tokens.append(255)
        else:
            tokens.append(int((x - min_val) / (max_val - min_val) * 255))

    state = 42

    def my_rand():
        nonlocal state
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        return state

    bootstrapped = []
    for _ in range(N):
        idx = my_rand() % N
        bootstrapped.append(tokens[idx])

    return bootstrapped


def expected_for(data):
    assert data
    n = len(data)
    min_val = min(data)
    max_val = max(data)

    tokens = []
    for x in data:
        if x == max_val:
            tokens.append(255)
        else:
            tokens.append(int((x - min_val) / (max_val - min_val) * 255))

    state = 42
    result = []
    for _ in range(n):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        result.append(tokens[state % n])
    return result


def read_integer_output(path):
    assert os.path.isfile(path), f'Program did not create output file {path}'
    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    result = []
    for i, value in enumerate(lines):
        try:
            result.append(int(value))
        except ValueError:
            pytest.fail(f'Line {i + 1} is not a valid integer: {value}')
    return result


def run_case(executable, tmp_path, name, data):
    input_path = tmp_path / f'{name}.txt'
    output_path = tmp_path / f'{name}.out'
    with open(input_path, 'w') as f:
        for value in data:
            f.write(f'{value:.9f}\n')

    proc = subprocess.run(
        [executable, str(input_path), str(output_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f'{executable} failed on a valid input with status {proc.returncode}: '
        f'{proc.stderr}'
    )
    assert read_integer_output(output_path) == expected_for(data)


def exercise_program(executable, tmp_path):
    with open('/home/user/raw_data.txt', 'r') as f:
        raw_data = [float(line.strip()) for line in f if line.strip()]
    run_case(executable, tmp_path, 'provided_raw_data', raw_data)

    run_case(
        executable,
        tmp_path,
        'fixed_edge_values',
        [-13.75, 8.5, -2.25, 91.125, 8.5, 0.0, 37.875, -13.75, 90.0],
    )

    rng = secrets.SystemRandom()
    random_data = [rng.randint(-900000, 900000) / 1000.0 for _ in range(73)]
    random_data[0] = -1000.125
    random_data[1] = 1000.875
    run_case(executable, tmp_path, 'random_runtime_data', random_data)


def assert_argument_handling(executable, tmp_path):
    input_path = tmp_path / 'argument_input.txt'
    output_path = tmp_path / 'argument_output.txt'
    input_path.write_text('0\n1\n')

    bad_argument_lists = [
        [],
        [str(input_path)],
        [str(input_path), str(output_path), 'extra'],
    ]
    for args in bad_argument_lists:
        proc = subprocess.run(
            [executable] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, (
            f'{executable} accepted an invalid argument count: {len(args)}'
        )


@pytest.fixture(scope='session')
def compiled_executable(tmp_path_factory):
    build_dir = tmp_path_factory.mktemp('source_build')
    output = build_dir / 'prepare_data_from_source'
    proc = subprocess.run(
        [
            'gcc', '-std=c11', '-O2', '-Wall', '-Wextra',
            '/home/user/prepare_data.c', '-o', str(output), '-lm'
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert proc.returncode == 0, f'prepare_data.c did not compile:\n{proc.stderr}'
    return str(output)


def test_c_source_exists():
    path = '/home/user/prepare_data.c'
    assert os.path.exists(path), f"Source file {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_executable_exists():
    path = '/home/user/prepare_data'
    assert os.path.exists(path), f"Executable {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_executable_is_compiled_binary():
    with open('/home/user/prepare_data', 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'prepare_data is not a compiled ELF executable.'


def test_output_file_exists():
    path = '/home/user/bootstrapped_tokens.txt'
    assert os.path.exists(path), f"Output file {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_output_contents():
    output_path = '/home/user/bootstrapped_tokens.txt'
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    golden_tokens = generate_golden_output()
    assert golden_tokens is not None, "Could not generate golden output because input file is missing."

    with open(output_path, 'r') as f:
        user_lines = [line.strip() for line in f if line.strip()]

    assert len(user_lines) == len(golden_tokens), f"Expected {len(golden_tokens)} lines in output, found {len(user_lines)}."

    for i, (user_val, expected_val) in enumerate(zip(user_lines, golden_tokens)):
        try:
            user_int = int(user_val)
        except ValueError:
            assert False, f"Line {i+1} in output is not a valid integer: {user_val}"

        assert user_int == expected_val, f"Mismatch at line {i+1}: expected {expected_val}, got {user_int}"


def test_submitted_executable_functionality(tmp_path):
    exercise_program('/home/user/prepare_data', tmp_path)
    assert_argument_handling('/home/user/prepare_data', tmp_path)


def test_source_functionality(compiled_executable, tmp_path):
    exercise_program(compiled_executable, tmp_path)
    assert_argument_handling(compiled_executable, tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
