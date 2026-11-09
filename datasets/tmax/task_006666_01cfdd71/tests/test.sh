#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import shutil
import subprocess
from pathlib import Path

SRC = Path('/home/user/pipeline/src')
LIB = SRC / 'libvm.so'
SCRIPT = Path('/home/user/pipeline/run_vm.py')
RESULT = Path('/home/user/pipeline/result.txt')


def clean_env():
    env = os.environ.copy()
    env.pop('LD_PRELOAD', None)
    env['LD_LIBRARY_PATH'] = ''
    return env


def run_script():
    return subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user/pipeline',
        env=clean_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )


def test_libvm_compiled():
    assert LIB.is_file(), f'Expected compiled library at {LIB} is missing. The CMake build may have failed.'


def test_run_vm_script_exists():
    assert SCRIPT.is_file(), f'Expected Python script at {SCRIPT} is missing.'


def test_cmake_rebuilds_and_links_mathops():
    LIB.unlink()
    subprocess.run(['cmake', '.'], cwd=SRC, check=True, timeout=30)
    subprocess.run(['cmake', '--build', '.'], cwd=SRC, check=True, timeout=30)
    assert LIB.is_file(), 'CMake did not rebuild libvm.so'

    info = subprocess.run(
        ['readelf', '-d', str(LIB)], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout
    assert re.search(r'NEEDED.*libmathops\.so', info), \
        'libvm.so is not dynamically linked against libmathops.so'


def test_library_executes_derived_bytecode():
    vm = ctypes.CDLL(str(LIB))
    execute = vm.execute_vm
    execute.argtypes = [ctypes.POINTER(ctypes.c_int)]
    execute.restype = ctypes.c_int

    seed = sum(str(LIB).encode('utf-8'))
    datasets = [
        [-3, 5, 8],
        [seed % 7 + 1, -(seed % 5 + 2), seed % 11 + 3],
    ]
    for values in datasets:
        code = []
        for index, value in enumerate(values):
            code.extend([1, value, 3])
            if index:
                code.append(2)
        code.append(0)
        array = (ctypes.c_int * len(code))(*code)
        expected = sum(value * value for value in values)
        assert execute(array) == expected

    invalid = (ctypes.c_int * 2)(2, 0)
    assert execute(invalid) == -1


def test_result_file_content_after_executing_script():
    if RESULT.exists():
        RESULT.unlink()
    completed = run_script()
    assert completed.returncode == 0, \
        f'run_vm.py failed:\nstdout: {completed.stdout}\nstderr: {completed.stderr}'
    assert RESULT.is_file(), f'Expected result file at {RESULT} is missing. Did the Python script run?'

    content = RESULT.read_text().strip()
    expected_value = sum(x * x for x in [4, 7, 2])
    assert content == str(expected_value), \
        f"Expected result file to contain '{expected_value}', but found '{content}'."


def test_script_calls_execute_vm_with_dataset_bytecode_and_uses_return_value(tmp_path):
    shim_source = tmp_path / 'shim.c'
    shim_library = tmp_path / 'libvm.so'
    capture = Path('/tmp/vm_bytecode.txt')
    sentinel = 170314159
    shim_source.write_text(r'''
#include <stdio.h>

int execute_vm(const int *bytecode) {
    FILE *out = fopen("/tmp/vm_bytecode.txt", "w");
    if (!out) return -1;
    int pc = 0;
    int stack_depth = 0;
    for (int steps = 0; steps < 64; ++steps) {
        int opcode = bytecode[pc++];
        fprintf(out, "%d\n", opcode);
        if (opcode == 0) {
            fclose(out);
            return 170314159;
        }
        if (opcode == 1) {
            int value = bytecode[pc++];
            fprintf(out, "%d\n", value);
            ++stack_depth;
        } else if (opcode == 2) {
            if (stack_depth < 2) { fclose(out); return -1; }
            --stack_depth;
        } else if (opcode == 3) {
            if (stack_depth < 1) { fclose(out); return -1; }
        } else {
            fclose(out);
            return -1;
        }
    }
    fclose(out);
    return -1;
}
''')
    subprocess.run(
        ['gcc', '-shared', '-fPIC', str(shim_source), '-o', str(shim_library)],
        check=True,
    )

    backup = tmp_path / 'real-libvm.so'
    shutil.copy2(LIB, backup)
    try:
        shutil.copy2(shim_library, LIB)
        capture.unlink(missing_ok=True)
        RESULT.unlink(missing_ok=True)
        completed = run_script()
        assert completed.returncode == 0, \
            f'run_vm.py failed against the execute_vm test library: {completed.stderr}'
        assert capture.is_file(), 'run_vm.py did not call execute_vm through the required shared library'
        assert RESULT.is_file(), 'run_vm.py did not write result.txt'
        assert RESULT.read_text().strip() == str(sentinel), \
            'run_vm.py did not write the value returned by execute_vm'

        code = [int(line) for line in capture.read_text().splitlines()]
        stack = []
        pc = 0
        while pc < len(code):
            opcode = code[pc]
            pc += 1
            if opcode == 0:
                break
            if opcode == 1:
                assert pc < len(code), 'OP_PUSH is missing its operand'
                stack.append(('push', code[pc]))
                pc += 1
            elif opcode == 3:
                assert stack, 'OP_SQUARE underflowed the stack'
                stack.append(('square', stack.pop()))
            elif opcode == 2:
                assert len(stack) >= 2, 'OP_ADD underflowed the stack'
                right = stack.pop()
                left = stack.pop()
                stack.append(('add', left, right))
            else:
                raise AssertionError(f'Unknown opcode {opcode} in generated bytecode')
        else:
            raise AssertionError('Generated bytecode has no OP_END')

        assert pc == len(code), 'Generated bytecode contains data after OP_END'
        assert len(stack) == 1, 'Generated bytecode does not leave exactly one result'

        leaves = []
        def collect(node):
            if node[0] == 'add':
                collect(node[1])
                collect(node[2])
            else:
                assert node[0] == 'square' and node[1][0] == 'push', \
                    'Each dataset value must be pushed and squared before addition'
                leaves.append(node[1][1])
        collect(stack[0])
        assert sorted(leaves) == [2, 4, 7], \
            'Bytecode must calculate the sum of squares of [4, 7, 2]'
    finally:
        shutil.copy2(backup, LIB)
        RESULT.unlink(missing_ok=True)
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
