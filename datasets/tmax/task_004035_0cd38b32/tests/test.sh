#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

BASE = Path('/home/user/stack-vm')
BIN = BASE / 'build' / 'bin' / 'vm-cli'
LIB = BASE / 'build' / 'lib' / 'libvm_engine.so'


def run(cmd, **kwargs):
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('text', True)
    kwargs.setdefault('timeout', 30)
    return subprocess.run(cmd, **kwargs)


def assert_real_linked_build(bin_path, lib_path):
    assert bin_path.is_file(), f'Executable not found at {bin_path}'
    assert lib_path.is_file(), f'Shared library not found at {lib_path}'
    assert os.access(bin_path, os.X_OK), f'{bin_path} is not executable'

    exe_header = run(['readelf', '-h', str(bin_path)])
    assert exe_header.returncode == 0, f'{bin_path} is not an ELF executable: {exe_header.stderr}'
    lib_header = run(['readelf', '-h', str(lib_path)])
    assert lib_header.returncode == 0, f'{lib_path} is not an ELF shared library: {lib_header.stderr}'

    dynamic = run(['readelf', '-d', str(bin_path)])
    assert dynamic.returncode == 0, dynamic.stderr
    assert 'Shared library: [libvm_engine.so]' in dynamic.stdout, \
        'vm-cli does not have a dynamic dependency on libvm_engine.so'
    assert '(RPATH)' in dynamic.stdout or '(RUNPATH)' in dynamic.stdout, \
        'vm-cli has no RPATH/RUNPATH for locating its shared library'

    env = os.environ.copy()
    env.pop('LD_LIBRARY_PATH', None)
    linked = run(['ldd', str(bin_path)], env=env)
    assert linked.returncode == 0, linked.stderr
    assert 'libvm_engine.so => not found' not in linked.stdout, linked.stdout
    assert str(lib_path.resolve()) in linked.stdout, \
        f'vm-cli did not resolve vm_engine to {lib_path}; ldd output:\n{linked.stdout}'

    exports = run(['nm', '-D', '-C', str(lib_path)])
    assert exports.returncode == 0, exports.stderr
    for symbol in ('VMEngine::push(int)', 'VMEngine::add()', 'VMEngine::sub()',
                   'VMEngine::save_state', 'VMEngine::load_state', 'VMEngine::print_top'):
        assert symbol in exports.stdout, f'{lib_path} does not export {symbol}'

    imports = run(['nm', '-D', '-C', str(bin_path)])
    assert imports.returncode == 0, imports.stderr
    assert ' U VMEngine::push(int)' in imports.stdout
    assert ' U VMEngine::save_state' in imports.stdout
    assert ' U VMEngine::load_state' in imports.stdout


def test_directory_structure():
    """Verify that the source files have been reorganized correctly."""
    base_dir = '/home/user/stack-vm'

    assert os.path.isfile(os.path.join(base_dir, 'include', 'vm_engine.h')), 'include/vm_engine.h is missing.'
    assert os.path.isfile(os.path.join(base_dir, 'src', 'vm_engine.cpp')), 'src/vm_engine.cpp is missing.'
    assert os.path.isfile(os.path.join(base_dir, 'src', 'main.cpp')), 'src/main.cpp is missing.'

    assert not os.path.exists(os.path.join(base_dir, 'vm_engine.h')), 'vm_engine.h should be moved to include/'
    assert not os.path.exists(os.path.join(base_dir, 'vm_engine.cpp')), 'vm_engine.cpp should be moved to src/'
    assert not os.path.exists(os.path.join(base_dir, 'main.cpp')), 'main.cpp should be moved to src/'


def test_build_outputs():
    """Verify that the CMake configuration correctly built the targets in the specified directories."""
    assert os.path.isfile(BIN), f'Executable not found at {BIN}. Check CMake output directories.'
    assert os.path.isfile(LIB), f'Shared library not found at {LIB}. Check CMake output directories.'


def test_executable_rpath():
    """Verify that the executable runs without LD_LIBRARY_PATH, implying correct RPATH."""
    env = os.environ.copy()
    env.pop('LD_LIBRARY_PATH', None)
    try:
        result = subprocess.run([str(BIN)], env=env, capture_output=True, text=True)
        assert result.returncode == 1, f'Expected return code 1 (usage error), got {result.returncode}. Output: {result.stderr}'
        assert 'Usage:' in result.stderr, f'Executable failed to run properly. Missing shared library? Error: {result.stderr}'
    except FileNotFoundError:
        pytest.fail(f'Executable {BIN} not found.')


def test_result_log():
    """Verify that the final output log contains the correct result."""
    log_path = '/home/user/result.log'
    assert os.path.isfile(log_path), f'Result log not found at {log_path}. Did you run the emulator with prog2.txt?'
    with open(log_path, 'r') as f:
        content = f.read().strip()
    assert content == '25', f"Expected result log to contain '25', but got '{content}'."


def test_existing_artifacts_are_real_and_linked():
    assert_real_linked_build(BIN, LIB)


@pytest.fixture(scope='session')
def clean_build():
    build_dir = Path(tempfile.mkdtemp(prefix='stack_vm_clean_build_'))
    try:
        configured = run(['cmake', '-S', str(BASE), '-B', str(build_dir)], timeout=60)
        assert configured.returncode == 0, \
            f'Clean CMake configuration failed:\n{configured.stdout}\n{configured.stderr}'
        built = run(['cmake', '--build', str(build_dir), '--parallel', '2'], timeout=60)
        assert built.returncode == 0, f'Clean build failed:\n{built.stdout}\n{built.stderr}'

        clean_bin = build_dir / 'bin' / 'vm-cli'
        clean_lib = build_dir / 'lib' / 'libvm_engine.so'
        assert_real_linked_build(clean_bin, clean_lib)
        yield clean_bin
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_cmake_builds_from_scratch(clean_build):
    env = os.environ.copy()
    env.pop('LD_LIBRARY_PATH', None)
    result = run([str(clean_build)], env=env)
    assert result.returncode == 1
    assert 'Usage:' in result.stderr


def test_provided_programs_execute():
    env = os.environ.copy()
    env.pop('LD_LIBRARY_PATH', None)
    state = Path('/home/user/state.bin')
    result_log = Path('/home/user/result.log')
    state.unlink(missing_ok=True)
    result_log.unlink(missing_ok=True)

    first = run([str(BIN), str(BASE / 'prog1.txt')], env=env)
    assert first.returncode == 0, first.stderr
    assert state.is_file(), 'prog1.txt did not create /home/user/state.bin'

    second = run([str(BIN), str(BASE / 'prog2.txt')], env=env)
    assert second.returncode == 0, second.stderr
    assert result_log.is_file(), 'prog2.txt did not create /home/user/result.log'
    assert result_log.read_text().strip() == '25'


def test_randomized_binary_save_load_and_execution(clean_build, tmp_path):
    """Exercise independently derived states across separate VM processes."""
    env = os.environ.copy()
    env.pop('LD_LIBRARY_PATH', None)
    rng = secrets.SystemRandom()
    size_width = ctypes.sizeof(ctypes.c_size_t)

    for case in range(8):
        values = [rng.randint(-5000, 5000) for _ in range(rng.randint(4, 10))]
        state_path = tmp_path / f'state_{case}_{secrets.token_hex(6)}.bin'
        output_path = tmp_path / f'output_{case}_{secrets.token_hex(6)}.log'
        save_script = tmp_path / f'save_{case}.txt'
        load_script = tmp_path / f'load_{case}.txt'

        save_script.write_text(''.join(f'PUSH {value}\n' for value in values) + f'SAVE {state_path}\n')
        saved = run([str(clean_build), str(save_script)], env=env)
        assert saved.returncode == 0, saved.stderr
        assert state_path.is_file(), 'SAVE did not create the requested state file'

        raw = state_path.read_bytes()
        assert len(raw) >= size_width
        count = int.from_bytes(raw[:size_width], byteorder=os.sys.byteorder, signed=False)
        assert count == len(values), 'Serialized state does not contain the correct stack size'
        assert len(raw) == size_width + count * ctypes.sizeof(ctypes.c_int), \
            'Serialized state is not the expected binary size_t-plus-int-array format'
        decoded = list(struct.unpack('@' + ('i' * count), raw[size_width:]))
        assert decoded == values, 'Serialized binary stack contents are incorrect'

        expected_stack = values[:]
        commands = [f'LOAD {state_path}']
        while len(expected_stack) > 1:
            op = rng.choice(('ADD', 'SUB'))
            a = expected_stack.pop()
            b = expected_stack.pop()
            expected_stack.append(a + b if op == 'ADD' else b - a)
            commands.append(op)

        extra = rng.randint(-1000, 1000)
        commands.append(f'PUSH {extra}')
        expected_stack.append(extra)
        final_op = rng.choice(('ADD', 'SUB'))
        a = expected_stack.pop()
        b = expected_stack.pop()
        expected_stack.append(a + b if final_op == 'ADD' else b - a)
        commands.extend((final_op, f'PRINT {output_path}'))
        load_script.write_text('\n'.join(commands) + '\n')

        loaded = run([str(clean_build), str(load_script)], env=env)
        assert loaded.returncode == 0, loaded.stderr
        assert output_path.is_file(), 'PRINT did not create the requested output file'
        assert output_path.read_text().strip() == str(expected_stack[-1]), \
            'VM produced the wrong result after loading and operating on serialized state'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
