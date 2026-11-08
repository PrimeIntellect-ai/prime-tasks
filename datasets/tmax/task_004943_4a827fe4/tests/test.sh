#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import os
from pathlib import Path
import random
import shutil
import subprocess

import pytest

ROOT = Path('/app/rust_lib')
SOLUTION = Path('/home/user/solution.py')
MASK = (1 << 64) - 1


def run(cmd, cwd=None, env=None, timeout=120):
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)


def encode_varint(value: int) -> bytes:
    if value == 0:
        return b'\x00'
    out = bytearray()
    while value:
        byte = value & 0x7f
        value >>= 7
        out.append(byte | (0x80 if value else 0))
    return bytes(out)


def encode_operations(values: list[int]) -> str:
    payload = b''.join(encode_varint(v) for v in values)
    if not payload:
        return ''
    return (b'\x0a' + encode_varint(len(payload)) + payload).hex()


def expected_oracle(values: list[int]) -> str:
    state = 0
    for value in values:
        state = (state + value) * 2
    return str(state)


def run_solution(values, env=None):
    return run(['python3', str(SOLUTION), encode_operations(values)], env=env, timeout=10)


def clean_and_build():
    cargo = run(['cargo', 'clean'], cwd=ROOT)
    assert cargo.returncode == 0, cargo.stderr

    cargo = run(['cargo', 'build', '--release'], cwd=ROOT)
    assert cargo.returncode == 0, f'cargo build --release failed:\n{cargo.stdout}\n{cargo.stderr}'

    for path in ('CMakeCache.txt', 'CMakeFiles', 'Makefile', 'cmake_install.cmake', 'libwrapper.so'):
        target = ROOT / path
        if target.is_dir():
            shutil.rmtree(target)
        elif target.exists() or target.is_symlink():
            target.unlink()

    cmake = run(['cmake', '.'], cwd=ROOT)
    assert cmake.returncode == 0, f'cmake . failed:\n{cmake.stdout}\n{cmake.stderr}'
    make = run(['make'], cwd=ROOT)
    assert make.returncode == 0, f'make failed:\n{make.stdout}\n{make.stderr}'


def test_solution_exists_and_schema_was_compiled():
    assert SOLUTION.is_file(), 'The solution script /home/user/solution.py does not exist.'
    candidates = list(Path('/home/user').rglob('*_pb2.py')) + list(Path('/app').rglob('*_pb2.py'))
    assert candidates, 'No Python protobuf module generated from the recovered schema was found.'

    valid = False
    for candidate in candidates:
        try:
            spec = importlib.util.spec_from_file_location('candidate_pb2', candidate)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            desc = module.DESCRIPTOR.message_types_by_name.get('Operations')
            if desc is None:
                continue
            field = desc.fields_by_name.get('values')
            if field and field.number == 1 and field.label == field.LABEL_REPEATED and field.type == field.TYPE_UINT64:
                valid = True
                break
        except Exception:
            continue
    assert valid, 'Generated protobuf module does not contain repeated uint64 Operations.values = 1.'


def test_rust_and_cmake_build_and_link():
    clean_and_build()
    rust_so = ROOT / 'target/release/libaccum.so'
    wrapper_so = ROOT / 'libwrapper.so'
    assert rust_so.is_file(), 'cargo did not produce target/release/libaccum.so'
    assert wrapper_so.is_file(), 'CMake did not produce libwrapper.so'

    dynamic = run(['readelf', '-d', str(wrapper_so)])
    assert dynamic.returncode == 0, dynamic.stderr
    assert 'libaccum.so' in dynamic.stdout, 'libwrapper.so has no dynamic dependency on libaccum.so'

    old = os.environ.get('LD_LIBRARY_PATH', '')
    os.environ['LD_LIBRARY_PATH'] = f'{ROOT / "target/release"}:{old}'
    lib = ctypes.CDLL(str(wrapper_so))
    fn = lib.call_process_value
    fn.argtypes = [ctypes.c_uint64, ctypes.c_uint64]
    fn.restype = ctypes.c_uint64
    assert fn(0, 7) == 14
    assert fn(14, 5) == 38
    assert fn(MASK, 1) == 0


def test_fuzz_equivalence():
    oracle_path = '/app/oracle'
    assert os.path.isfile(oracle_path), f'Oracle not found at {oracle_path}'
    assert os.access(oracle_path, os.X_OK), f'Oracle at {oracle_path} is not executable'

    random.seed(42)
    for _ in range(100):
        length = random.randint(0, 20)
        values = [random.randint(0, MASK) for _ in range(length)]
        result = run_solution(values)
        assert result.returncode == 0, f'Agent script failed. Stderr: {result.stderr}'
        assert result.stdout.strip() == expected_oracle(values), (
            f'Mismatch on input {encode_operations(values)}\n'
            f'Expected: {expected_oracle(values)}\nGot: {result.stdout.strip()}'
        )


def test_python_output_really_uses_the_wrapper_and_rust():
    source = ROOT / 'src/lib.rs'
    original = source.read_bytes()
    replacement = b'''#[no_mangle]\npub extern "C" fn process_value(current_state: u64, value: u64) -> u64 {\n    current_state.wrapping_mul(3).wrapping_add(value).wrapping_add(7)\n}\n'''
    try:
        source.write_bytes(replacement)
        cargo = run(['cargo', 'build', '--release'], cwd=ROOT)
        assert cargo.returncode == 0, f'Failed to rebuild instrumented Rust library: {cargo.stderr}'
        make = run(['make'], cwd=ROOT)
        assert make.returncode == 0, f'Failed to rebuild wrapper: {make.stderr}'

        values = [3, 5, 11]
        state = 0
        for value in values:
            state = (state * 3 + value + 7) & MASK
        env = os.environ.copy()
        env['LD_LIBRARY_PATH'] = f'{ROOT / "target/release"}:{env.get("LD_LIBRARY_PATH", "")}'
        result = run_solution(values, env=env)
        assert result.returncode == 0, f'Agent failed with instrumented wrapper: {result.stderr}'
        assert result.stdout.strip() == str(state), (
            'solution.py output did not follow the instrumented Rust function through libwrapper.so; '
            'it appears to compute the answer independently or invoke the oracle.'
        )
    finally:
        source.write_bytes(original)
        run(['cargo', 'build', '--release'], cwd=ROOT)
        run(['make'], cwd=ROOT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
