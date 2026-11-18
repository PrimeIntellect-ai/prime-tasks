#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
import pytest

@pytest.fixture(scope='session', autouse=True)
def compile_and_execute_analyzer():
    cpp_path = '/home/user/analyzer.cpp'
    executable_path = '/tmp/analyzer_submission'

    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} does not exist. You must write the program to this file."

    for output_path in ('/home/user/archive.bin', '/home/user/anomaly.txt'):
        if os.path.lexists(output_path):
            if os.path.isdir(output_path) and not os.path.islink(output_path):
                raise AssertionError(f"Expected output path {output_path} is a directory.")
            os.remove(output_path)

    try:
        compilation = subprocess.run(
            ['g++', '-std=c++17', '-O2', cpp_path, '-o', executable_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError('Compiling analyzer.cpp timed out.')

    assert compilation.returncode == 0, f"analyzer.cpp failed to compile:\n{compilation.stdout}"
    assert os.path.isfile(executable_path), 'Compilation did not produce an executable.'

    try:
        execution = subprocess.run(
            [executable_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError('The compiled analyzer program timed out.')

    assert execution.returncode == 0, f"The compiled analyzer program failed:\n{execution.stdout}"

def test_anomaly_file():
    anomaly_path = '/home/user/anomaly.txt'
    assert os.path.isfile(anomaly_path), f"File {anomaly_path} does not exist. The anomaly detection result was not saved."

    with open(anomaly_path, 'r') as f:
        content = f.read().strip()

    assert content == 'output_73.txt', f"Expected anomaly file to be 'output_73.txt', but got '{content}'."

def test_archive_bin():
    archive_path = '/home/user/archive.bin'
    assert os.path.isfile(archive_path), f"File {archive_path} does not exist. The binary archive was not created."

    # Recompute expected points
    files = sorted(f for f in os.listdir('/home/user/model_outputs') if f.endswith('.txt'))
    expected_points = []

    for f in files:
        with open(os.path.join('/home/user/model_outputs', f), 'r') as file:
            text = file.read()
        tokens = text.split()
        X = 0
        Y = 0
        for t in tokens:
            L = len(t)
            ascii_sum = sum(ord(c) for c in t)
            if ascii_sum % 2 == 0:
                X += L
            else:
                X -= L

            if ascii_sum % 3 == 0:
                Y += L
            else:
                Y -= L
        expected_points.append((X, Y))

    # Read binary file
    with open(archive_path, 'rb') as f:
        data = f.read()

    assert len(data) == 800, f"Expected archive.bin to be exactly 800 bytes, got {len(data)} bytes."

    # Unpack binary data using native byte order and 32-bit signed integers
    actual_points = []
    for i in range(0, 800, 8):
        x = int.from_bytes(data[i:i+4], byteorder=sys.byteorder, signed=True)
        y = int.from_bytes(data[i+4:i+8], byteorder=sys.byteorder, signed=True)
        actual_points.append((x, y))

    for i, (actual, expected) in enumerate(zip(actual_points, expected_points)):
        assert actual == expected, f"Mismatch at file {files[i]}: expected (X, Y) = {expected}, got {actual}."

def test_analyzer_cpp_exists():
    cpp_path = '/home/user/analyzer.cpp'
    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} does not exist. You must write the program to this file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
