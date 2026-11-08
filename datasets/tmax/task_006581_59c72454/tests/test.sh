#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess


def calculate_expected():
    parsed_data = []
    with open('/home/user/data.csv', 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            seq = [0.0 if token == 'NA' else float(token) for token in parts[1].split('|')]
            parsed_data.append((seq, float(parts[2])))

    best_w = None
    best_mse = float('inf')
    for w in [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]:
        total_mse = 0.0
        for fold in range(5):
            val_start = fold * 5
            val_end = val_start + 5
            train_data = parsed_data[:val_start] + parsed_data[val_end:]
            val_data = parsed_data[val_start:val_end]

            bias = sum(
                target - sum(value * (w ** j) for j, value in enumerate(seq))
                for seq, target in train_data
            ) / 20.0

            fold_mse = sum(
                (target - (sum(value * (w ** j) for j, value in enumerate(seq)) + bias)) ** 2
                for seq, target in val_data
            ) / 5.0
            total_mse += fold_mse

        cv_mse = total_mse / 5.0
        if cv_mse < best_mse:
            best_mse = cv_mse
            best_w = w

    return f'Best w: {best_w:.1f}, MSE: {best_mse:.4f}'


def test_tune_cpp_exists_and_non_empty():
    """Test that the C++ source file exists and is not empty."""
    cpp_path = '/home/user/tune.cpp'
    assert os.path.exists(cpp_path), f'File {cpp_path} does not exist.'
    assert os.path.isfile(cpp_path), f'Path {cpp_path} is not a file.'
    assert os.path.getsize(cpp_path) > 0, f'File {cpp_path} is empty.'


def test_result_txt_matches_expected():
    """Compile and run the submitted program, then check its generated output."""
    expected_content = calculate_expected()
    result_path = '/home/user/result.txt'
    executable_path = '/home/user/tune'

    if os.path.lexists(result_path):
        os.remove(result_path)

    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', '/home/user/tune.cpp', '-o', executable_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f'C++ compilation failed:\n{compile_result.stderr}'
    assert os.path.isfile(executable_path), f'Compiler did not create {executable_path}.'

    run_result = subprocess.run(
        [executable_path],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, f'Program execution failed:\n{run_result.stderr}'

    assert os.path.exists(result_path), f'File {result_path} does not exist. Did your C++ program write it?'
    assert os.path.isfile(result_path), f'Path {result_path} is not a file.'

    with open(result_path, 'r') as f:
        result_content = f.read().strip()

    assert result_content == expected_content, (
        f"Content of {result_path} ('{result_content}') does not match expected output ('{expected_content}')."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
