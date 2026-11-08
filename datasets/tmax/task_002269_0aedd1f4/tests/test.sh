#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import re
import shutil
import subprocess
import time
from pathlib import Path

import pytest

PROJECT = Path('/home/user/project')
AGENT_BIN = PROJECT / 'target/release/matrix_solver'
REF_BIN = Path('/app/reference_c_impl')
MOD = 9973


def matrix_result(n):
    def mul(a, b):
        return [
            (a[0] * b[0] + a[1] * b[2]) % MOD,
            (a[0] * b[1] + a[1] * b[3]) % MOD,
            (a[2] * b[0] + a[3] * b[2]) % MOD,
            (a[2] * b[1] + a[3] * b[3]) % MOD,
        ]

    result = [1, 0, 0, 1]
    base = [1, 1, 1, 0]
    while n:
        if n & 1:
            result = mul(result, base)
        base = mul(base, base)
        n >>= 1
    return f'Result: [{result[0]}, {result[1]}, {result[2]}, {result[3]}]'


def run_checked(cmd, timeout=30, cwd=None, env=None):
    return subprocess.run(
        cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout
    )


def rust_defines_compute_matrix_power(text):
    for match in re.finditer(r'\bfn\s+compute_matrix_power\s*\(', text):
        pos = match.end() - 1
        depth = 0
        while pos < len(text):
            if text[pos] == '(':
                depth += 1
            elif text[pos] == ')':
                depth -= 1
                if depth == 0:
                    pos += 1
                    break
            pos += 1
        while pos < len(text):
            if text[pos] == '{':
                return True
            if text[pos] == ';':
                break
            pos += 1
    return False


def patch_main_argument(main_rs, exponent):
    text = main_rs.read_text()
    main_match = re.search(r'\bfn\s+main\s*\([^)]*\)\s*\{', text)
    assert main_match, 'src/main.rs does not define fn main()'

    body_start = main_match.end()
    depth = 1
    pos = body_start
    while pos < len(text) and depth:
        if text[pos] == '{':
            depth += 1
        elif text[pos] == '}':
            depth -= 1
        pos += 1
    assert depth == 0, 'Could not parse the body of fn main()'
    body_end = pos - 1

    replacements = []
    search_pos = body_start
    while True:
        name = text.find('compute_matrix_power', search_pos, body_end)
        if name < 0:
            break
        open_paren = text.find('(', name + len('compute_matrix_power'), body_end)
        if open_paren < 0:
            break
        paren_depth = 1
        close_paren = open_paren + 1
        while close_paren < body_end and paren_depth:
            if text[close_paren] == '(':
                paren_depth += 1
            elif text[close_paren] == ')':
                paren_depth -= 1
            close_paren += 1
        assert paren_depth == 0, 'Could not parse compute_matrix_power call in main'
        replacements.append((open_paren + 1, close_paren - 1))
        search_pos = close_paren

    assert replacements, (
        'fn main() must invoke the translated Rust compute_matrix_power function'
    )
    for start, end in reversed(replacements):
        text = text[:start] + str(exponent) + text[end:]
    main_rs.write_text(text)


def test_executable_exists_and_is_native():
    assert AGENT_BIN.is_file(), f'Agent binary not found at {AGENT_BIN}'
    assert os.access(AGENT_BIN, os.X_OK), f'{AGENT_BIN} is not executable'
    assert AGENT_BIN.read_bytes()[:4] == b'\x7fELF', 'matrix_solver must be a native executable'
    assert REF_BIN.is_file(), 'Reference binary missing at /app/reference_c_impl'
    assert not filecmp.cmp(AGENT_BIN, REF_BIN, shallow=False), (
        'Submission must not be a byte-identical copy of the reference executable'
    )


def test_translation_is_in_rust_not_c():
    rust_files = list((PROJECT / 'src').rglob('*.rs'))
    assert rust_files, 'No Rust source files found'
    assert any(rust_defines_compute_matrix_power(p.read_text()) for p in rust_files), (
        'compute_matrix_power must be implemented in Rust'
    )

    c_file = PROJECT / 'clib/math_core.c'
    if c_file.exists():
        c_text = c_file.read_text()
        c_definition = re.search(
            r'\b(?:void|int|long|long\s+long|unsigned|static)\b[^;{}]*'
            r'\bcompute_matrix_power\s*\([^;{}]*\)\s*\{',
            c_text,
            re.S,
        )
        assert not c_definition, 'The old C compute_matrix_power implementation must be removed'


def test_speedup_and_fixed_output():
    start_ref = time.perf_counter()
    ref_proc = run_checked([str(REF_BIN)], timeout=30)
    ref_duration = time.perf_counter() - start_ref
    assert ref_proc.returncode == 0, f'Reference executable failed: {ref_proc.stderr}'

    start_agent = time.perf_counter()
    agent_proc = run_checked([str(AGENT_BIN)], timeout=5)
    agent_duration = time.perf_counter() - start_agent
    assert agent_proc.returncode == 0, (
        f'Agent binary failed with exit code {agent_proc.returncode}: {agent_proc.stderr}'
    )

    expected = matrix_result(1048576)
    assert agent_proc.stdout.strip() == expected, (
        f'Expected exactly {expected!r}, got {agent_proc.stdout.strip()!r}'
    )

    speedup = ref_duration / agent_duration if agent_duration > 0 else float('inf')
    assert speedup >= 20.0, (
        f'Performance speedup was {speedup:.2f}x, below the required 20.0x '
        f'(reference {ref_duration:.6f}s, agent {agent_duration:.6f}s)'
    )


def test_function_handles_unseen_large_exponents(tmp_path):
    copied = tmp_path / 'project'
    shutil.copytree(PROJECT, copied, ignore=shutil.ignore_patterns('target'))
    main_rs = copied / 'src/main.rs'
    original_main = main_rs.read_text()

    rng = random.SystemRandom()
    exponents = [
        rng.randrange(10**11, 10**12),
        rng.randrange(10**12, 4 * 10**12),
    ]
    target_dir = tmp_path / 'target'
    env = os.environ.copy()
    env['CARGO_TARGET_DIR'] = str(target_dir)
    cargo = shutil.which('cargo') or '/root/.cargo/bin/cargo'

    for exponent in exponents:
        main_rs.write_text(original_main)
        patch_main_argument(main_rs, exponent)
        build = run_checked(
            [cargo, 'build', '--release', '--offline'],
            timeout=120,
            cwd=str(copied),
            env=env,
        )
        assert build.returncode == 0, (
            f'Modified project failed to build for exponent {exponent}:\n{build.stderr}'
        )

        rebuilt = target_dir / 'release/matrix_solver'
        proc = run_checked([str(rebuilt)], timeout=3)
        assert proc.returncode == 0, (
            f'matrix_solver failed for exponent {exponent}: {proc.stderr}'
        )
        expected = matrix_result(exponent)
        assert proc.stdout.strip() == expected, (
            f'compute_matrix_power is not general binary exponentiation. '
            f'For exponent {exponent}, expected {expected!r}, '
            f'got {proc.stdout.strip()!r}'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
