#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
from pathlib import Path

import pytest
import xxhash

ROOT = Path('/app/vendored/xxHash-0.8.2')
LIB = ROOT / 'libxxhash.a'
MAKEFILE = ROOT / 'Makefile'
SOURCE = Path('/home/user/fast_hasher.cpp')
EXECUTABLE = Path('/home/user/fast_hasher')
ORACLE = Path('/home/user/legacy_hasher.py')
REBUILT = Path('/tmp/fast_hasher_rebuilt')


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kwargs)


def assert_valid_archive():
    listing = run(['ar', 't', str(LIB)])
    assert listing.returncode == 0, f'libxxhash.a is not a valid archive: {listing.stderr}'
    assert listing.stdout.strip(), 'libxxhash.a is an empty archive'

    symbols = run(['nm', '-g', '--defined-only', str(LIB)])
    assert symbols.returncode == 0, f'Unable to inspect libxxhash.a: {symbols.stderr}'
    assert re.search(r'\bXXH32\b', symbols.stdout), 'libxxhash.a does not define XXH32'


def assert_native_xxhash_executable(path):
    data = Path(path).read_bytes()[:4]
    assert data == b'\x7fELF', f'{path} is not a native ELF executable'

    elf = run(['readelf', '-h', str(path)])
    assert elf.returncode == 0, f'{path} is not a valid ELF file: {elf.stderr}'

    symbols = run(['nm', '-g', str(path)])
    assert symbols.returncode == 0, f'Unable to inspect symbols in {path}: {symbols.stderr}'
    assert re.search(r'\bXXH32\b', symbols.stdout), f'{path} does not contain the statically linked XXH32 implementation'

    dynamic = run(['readelf', '-d', str(path)])
    assert dynamic.returncode == 0, f'Unable to inspect linkage of {path}: {dynamic.stderr}'
    assert 'libxxhash' not in dynamic.stdout.lower(), f'{path} dynamically depends on libxxhash instead of using the archive'


def expected_output(lines):
    output = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        digest = xxhash.xxh32(stripped, seed=42).intdigest()
        if digest % 2 == 0:
            output.append(f'{digest:08x} {stripped[::-1]}')
    return ''.join(line + '\n' for line in output)


def test_libxxhash_built_and_makefile_repaired():
    # Preserve the original existence assertion.
    assert os.path.isfile(LIB), f'Static library not found at {LIB}. The Makefile perturbation might not be fixed or make was not run.'
    assert os.path.isfile(MAKEFILE), f'Makefile not found at {MAKEFILE}'
    assert_valid_archive()

    make_text = MAKEFILE.read_text(errors='replace')
    assert not re.search(r'^\s*AR\s*(?:\?|:)?=\s*/bin/false\s*$', make_text, re.MULTILINE), 'The broken AR assignment remains in the Makefile'

    clean = run(['make', 'clean'], cwd=ROOT)
    assert clean.returncode == 0, f'make clean failed: {clean.stdout}\n{clean.stderr}'
    if LIB.exists():
        LIB.unlink()
    build = run(['make', 'libxxhash.a'], cwd=ROOT)
    assert build.returncode == 0, f'Makefile cannot build libxxhash.a: {build.stdout}\n{build.stderr}'
    assert os.path.isfile(LIB), 'make did not recreate libxxhash.a'
    assert_valid_archive()


def test_cpp_source_and_executable():
    # Preserve the original executable assertions.
    assert os.path.isfile(EXECUTABLE), f'Executable not found at {EXECUTABLE}'
    assert os.access(EXECUTABLE, os.X_OK), f'File at {EXECUTABLE} is not executable'

    assert os.path.isfile(SOURCE), f'C++ source not found at {SOURCE}'
    assert not SOURCE.is_symlink(), 'fast_hasher.cpp must be an actual source file, not a symlink'
    source_text = SOURCE.read_text(errors='strict')
    assert re.search(r'^\s*#\s*include\s*[<"]xxhash\.h[>"]', source_text, re.MULTILINE), 'fast_hasher.cpp does not include xxhash.h'

    assert not EXECUTABLE.is_symlink(), 'fast_hasher must be an actual compiled executable, not a symlink'
    assert stat.S_ISREG(EXECUTABLE.stat().st_mode), 'fast_hasher is not a regular file'
    assert_native_xxhash_executable(EXECUTABLE)

    compile_proc = run([
        'g++', '-std=c++17', '-O2', '-I', str(ROOT), str(SOURCE),
        str(LIB), '-o', str(REBUILT)
    ])
    assert compile_proc.returncode == 0, f'fast_hasher.cpp cannot be compiled against the vendored archive: {compile_proc.stdout}\n{compile_proc.stderr}'
    assert_native_xxhash_executable(REBUILT)


def test_fuzz_equivalence():
    # Preserve the original oracle and agent existence assertions and comparison.
    assert os.path.isfile(ORACLE), f'Oracle not found at {ORACLE}'
    assert os.path.isfile(EXECUTABLE), f'Agent executable not found at {EXECUTABLE}'

    random.seed(42)
    printable_chars = [chr(i) for i in range(0x20, 0x7f)]
    inputs = []
    for _ in range(5000):
        length = random.randint(0, 256)
        inputs.append(''.join(random.choice(printable_chars) for _ in range(length)))
    input_data = '\n'.join(inputs) + '\n'

    oracle_proc = subprocess.run([str(ORACLE)], input=input_data, text=True, capture_output=True, timeout=30)
    assert oracle_proc.returncode == 0, f'Oracle failed: {oracle_proc.stderr}'

    agent_proc = subprocess.run([str(EXECUTABLE)], input=input_data, text=True, capture_output=True, timeout=30)
    assert agent_proc.returncode == 0, f'Agent executable failed: {agent_proc.stderr}'

    oracle_lines = oracle_proc.stdout.splitlines()
    agent_lines = agent_proc.stdout.splitlines()
    assert len(oracle_lines) == len(agent_lines), f'Output line count mismatch: oracle={len(oracle_lines)}, agent={len(agent_lines)}'
    for i, (expected, actual) in enumerate(zip(oracle_lines, agent_lines)):
        assert expected == actual, f'Mismatch at output line {i}. Expected: {expected!r}; got: {actual!r}'


def test_independently_derived_results_for_submitted_and_rebuilt_binaries():
    random.seed(918273)
    alphabet = ''.join(chr(i) for i in range(0x20, 0x7f))
    lines = ['', ' ', '\t', 'artifact.tar.gz', '  padded artifact  ', 'a', 'A' * 1024]
    for _ in range(7000):
        lines.append(''.join(random.choice(alphabet) for _ in range(random.randint(0, 512))))

    input_data = '\n'.join(lines) + '\n'
    expected = expected_output(lines)

    # A direct wrapper around the legacy script must not be able to satisfy this test.
    hidden_oracle = Path('/tmp/legacy_hasher.hidden-by-verifier')
    assert not hidden_oracle.exists()
    ORACLE.rename(hidden_oracle)
    try:
        for candidate in (EXECUTABLE, REBUILT):
            proc = subprocess.run(
                [str(candidate)], input=input_data, text=True,
                capture_output=True, timeout=30,
                env={**os.environ, 'PATH': '/usr/bin:/bin'}
            )
            assert proc.returncode == 0, f'{candidate} failed: {proc.stderr}'
            assert proc.stdout == expected, f'{candidate} is not bit-exact on independently checked fuzz input'
            assert proc.stderr == '', f'{candidate} wrote unexpected stderr: {proc.stderr}'
    finally:
        hidden_oracle.rename(ORACLE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
