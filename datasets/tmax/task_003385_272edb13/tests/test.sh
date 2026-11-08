#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
from pathlib import Path

import pytest

REPO = Path('/home/user/pr_review')
EXPECTED_OUTPUT = (
    b'PASS: 2+3*4 = 14 (CRC: 187)\n'
    b'PASS: 5*2+3 = 13 (CRC: 222)\n'
    b'PASS: 1+1+1 = 3 (CRC: 26)\n'
)

EXPECTED_HEADER = '''#ifndef EVAL_CRC_H
#define EVAL_CRC_H

#include <string>
#include <cstdint>

uint8_t calculate_crc8(const std::string& data);
int evaluate_expr(const std::string& expr);

#endif
'''

EXPECTED_TEST_RUNNER = '''#include "eval_crc.h"
#include <iostream>

void run_test(const std::string& expr, int expected_val, uint8_t expected_crc) {
    int val = evaluate_expr(expr);
    uint8_t crc = calculate_crc8(expr);

    if (val == expected_val && crc == expected_crc) {
        std::cout << "PASS: " << expr << " = " << val << " (CRC: " << (int)crc << ")\\n";
    } else {
        std::cout << "FAIL: " << expr << " | Expected " << expected_val << " / CRC " << (int)expected_crc 
                  << " | Got " << val << " / CRC " << (int)crc << "\\n";
    }
}

int main() {
    run_test("2+3*4", 14, 187);
    run_test("5*2+3", 13, 222);
    run_test("1+1+1", 3, 26);
    return 0;
}
'''


def test_make_actually_builds_and_runner_executes():
    # Remove all products ourselves so a stale or hand-created executable cannot pass.
    for name in ('test_runner', 'eval_crc.o', 'test_runner.o'):
        path = REPO / name
        if path.exists() or path.is_symlink():
            path.unlink()

    result = subprocess.run(
        ['make'], cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30
    )
    assert result.returncode == 0, (
        'make failed:\n' + result.stdout.decode(errors='replace') +
        result.stderr.decode(errors='replace')
    )

    exe_path = REPO / 'test_runner'
    assert exe_path.is_file(), f'Executable {exe_path} does not exist. Did you compile the project?'
    assert os.access(exe_path, os.X_OK), f'File {exe_path} is not executable.'
    assert exe_path.read_bytes()[:4] == b'\x7fELF', 'test_runner is not a compiled ELF executable.'

    run = subprocess.run(
        [str(exe_path)], cwd=REPO, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert run.returncode == 0, run.stderr.decode(errors='replace')
    assert run.stdout == EXPECTED_OUTPUT, 'test_runner did not produce the expected standard output.'
    Path('/tmp/actual_runner_stdout').write_bytes(run.stdout)


def test_test_results_log_exists():
    log_path = '/home/user/test_results.log'
    assert os.path.isfile(log_path), f'File {log_path} does not exist. Did you save the output?'


def test_test_results_log_content():
    log_path = '/home/user/test_results.log'
    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected_lines = [
        'PASS: 2+3*4 = 14 (CRC: 187)',
        'PASS: 5*2+3 = 13 (CRC: 222)',
        'PASS: 1+1+1 = 3 (CRC: 26)'
    ]

    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {log_path}."

    saved = Path(log_path).read_bytes()
    actual = Path('/tmp/actual_runner_stdout').read_bytes()
    assert saved == actual == EXPECTED_OUTPUT, (
        'test_results.log must contain exactly the standard output of ./test_runner.'
    )


def test_makefile_fixed():
    makefile_path = REPO / 'Makefile'
    assert makefile_path.is_file(), f'File {makefile_path} does not exist.'

    with makefile_path.open('r') as f:
        lines = f.readlines()

    for line in lines:
        if line.strip().startswith('g++') or line.strip().startswith('rm'):
            assert line.startswith('\t'), 'Makefile commands must start with a tab character.'


def test_eval_crc_cpp_fixed():
    cpp_path = REPO / 'eval_crc.cpp'
    assert cpp_path.is_file(), f'File {cpp_path} does not exist.'

    content = cpp_path.read_text()
    assert '0x07' in content and '0x70' not in content, (
        'The CRC polynomial bug was not fixed (should be 0x07).'
    )
    assert "if (op == '*') return 2;" in content or "return 2" in content.split("if (op == '*')[")[0], (
        "The operator precedence bug for '*' was not fixed."
    )
    assert '};' in content or '}' in content, 'The missing semicolon bug was not fixed.'


def test_executable_exists():
    exe_path = REPO / 'test_runner'
    assert exe_path.is_file(), f'Executable {exe_path} does not exist. Did you compile the project?'
    assert os.access(exe_path, os.X_OK), f'File {exe_path} is not executable.'


def crc8(data):
    crc = 0
    for byte in data.encode('ascii'):
        crc ^= byte
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) & 0xff) ^ 0x07
            else:
                crc = (crc << 1) & 0xff
    return crc


def expected_expr(expr):
    return sum(
        __import__('math').prod(int(ch) for ch in term.split('*'))
        for term in expr.split('+')
    )


def test_functions_independently_on_derived_cases():
    harness = Path('/tmp/eval_crc_harness.cpp')
    binary = Path('/tmp/eval_crc_harness')
    harness.write_text(r'''#include "eval_crc.h"
#include <iostream>
#include <string>
int main() {
    std::string expr;
    while (std::cin >> expr) {
        std::cout << evaluate_expr(expr) << " "
                  << static_cast<unsigned int>(calculate_crc8(expr)) << "\n";
    }
    return 0;
}
''')

    compile_result = subprocess.run(
        ['g++', '-std=c++11', '-Wall', '-Wextra', '-I', str(REPO),
         str(REPO / 'eval_crc.cpp'), str(harness), '-o', str(binary)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, compile_result.stderr.decode(errors='replace')

    cases = [
        '0', '7', '2*3', '2+3', '1+2*3', '9*8+7', '8+7*6+5',
        '2*3*4+5*6+7', '9+8*7*6+5*4+3', '0*9+8', '1+2+3*4*5'
    ]
    rng = random.SystemRandom()
    for _ in range(40):
        terms = rng.randint(1, 8)
        parts = [str(rng.randrange(10))]
        for _ in range(terms - 1):
            parts.append(rng.choice(['+', '*']))
            parts.append(str(rng.randrange(10)))
        cases.append(''.join(parts))

    run = subprocess.run(
        [str(binary)], input=('\n'.join(cases) + '\n').encode(),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert run.returncode == 0, run.stderr.decode(errors='replace')
    lines = run.stdout.decode().splitlines()
    assert len(lines) == len(cases)

    for expr, line in zip(cases, lines):
        fields = line.split()
        assert len(fields) == 2, f'Invalid harness output for {expr!r}: {line!r}'
        value, crc = map(int, fields)
        assert value == expected_expr(expr), f'evaluate_expr failed for {expr}'
        assert crc == crc8(expr), f'calculate_crc8 failed for {expr}'


def test_protected_files_were_not_modified():
    assert (REPO / 'eval_crc.h').read_text() == EXPECTED_HEADER, 'eval_crc.h was modified.'
    assert (REPO / 'test_runner.cpp').read_text() == EXPECTED_TEST_RUNNER, 'test_runner.cpp was modified.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
