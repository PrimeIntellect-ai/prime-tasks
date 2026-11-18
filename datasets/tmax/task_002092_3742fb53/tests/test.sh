#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

PROJECT = '/home/user/project'

EXPECTED_MAIN_RS = b'''mod magic;\n\nfn main() {\n    println!("The magic number is: {}", magic::MAGIC_NUMBER);\n}\n'''

EXPECTED_OPS_TXT = b'''1.0.9 ADD 500\n2.1.0 ADD 15\n2.0.99 MUL 100\n2.10.0 LSHIFT 3\n3.0.0 XOR 42\n10.0.0 SUB 2\n'''


def parse_version(v):
    return tuple(map(int, v.split('.')))


def assert_fixtures_unchanged():
    main_path = os.path.join(PROJECT, 'main.rs')
    ops_path = os.path.join(PROJECT, 'ops.txt')

    assert os.path.isfile(main_path), f"The file {main_path} is missing."
    assert os.path.isfile(ops_path), f"The file {ops_path} is missing."

    with open(main_path, 'rb') as f:
        assert f.read() == EXPECTED_MAIN_RS, 'main.rs was modified.'
    with open(ops_path, 'rb') as f:
        assert f.read() == EXPECTED_OPS_TXT, 'ops.txt was modified.'


def compute_magic_number(ops_path):
    reg = 0
    with open(ops_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 3:
                continue
            ver, op, val_str = parts[0], parts[1], parts[2]
            val = int(val_str)

            if parse_version(ver) >= (2, 1, 0):
                if op == 'ADD':
                    reg = (reg + val) % (1 << 32)
                elif op == 'SUB':
                    reg = (reg - val) % (1 << 32)
                elif op == 'MUL':
                    reg = (reg * val) % (1 << 32)
                elif op == 'XOR':
                    reg = (reg ^ val) % (1 << 32)
                elif op == 'LSHIFT':
                    reg = (reg << val) % (1 << 32)
                elif op == 'RSHIFT':
                    reg = (reg >> val) % (1 << 32)
    return reg


def test_source_fixtures_unchanged():
    assert_fixtures_unchanged()


def test_magic_rs_content():
    assert_fixtures_unchanged()
    magic_path = os.path.join(PROJECT, 'magic.rs')
    assert os.path.isfile(magic_path), f"The file {magic_path} was not generated."

    expected_magic_number = compute_magic_number(os.path.join(PROJECT, 'ops.txt'))

    with open(magic_path, 'r') as f:
        content = f.read().strip()

    expected_content = f"pub const MAGIC_NUMBER: u32 = {expected_magic_number};"
    assert content == expected_content, f"Content of {magic_path} is incorrect. Expected '{expected_content}', got '{content}'."


def test_executable_exists_and_is_compiled_project():
    assert_fixtures_unchanged()
    exe_path = os.path.join(PROJECT, 'main')
    assert os.path.isfile(exe_path), f"The compiled executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"The file {exe_path} is not executable."

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt_path = os.path.join(tmpdir, 'main')
        result = subprocess.run(
            ['rustc', 'main.rs', '-o', rebuilt_path],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"The Rust project does not compile: {result.stderr}"
        with open(exe_path, 'rb') as f:
            submitted_binary = f.read()
        with open(rebuilt_path, 'rb') as f:
            rebuilt_binary = f.read()
        assert submitted_binary == rebuilt_binary, 'main is not the executable produced by compiling the submitted Rust project.'


def test_output_txt_content_and_executable_output():
    assert_fixtures_unchanged()
    output_path = os.path.join(PROJECT, 'output.txt')
    exe_path = os.path.join(PROJECT, 'main')
    assert os.path.isfile(output_path), f"The file {output_path} does not exist."
    assert os.path.isfile(exe_path), f"The compiled executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"The file {exe_path} is not executable."

    expected_magic_number = compute_magic_number(os.path.join(PROJECT, 'ops.txt'))

    with open(output_path, 'r') as f:
        content = f.read().strip()

    expected_output = f"The magic number is: {expected_magic_number}"
    assert content == expected_output, f"Content of {output_path} is incorrect. Expected '{expected_output}', got '{content}'."

    result = subprocess.run(
        [exe_path],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"The compiled executable failed when run: {result.stderr}"
    assert result.stdout.strip() == expected_output, f"The compiled executable produced incorrect output: {result.stdout!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
