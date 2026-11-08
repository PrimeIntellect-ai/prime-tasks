#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/data_pipeline')


def run(cmd, *, cwd=PROJECT, env=None, timeout=180):
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def parse_result(output):
    match = re.fullmatch(
        r'\s*Result:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*',
        output,
    )
    assert match, f'Unexpected program output: {output!r}'
    return float(match.group(1))


def test_build_rs_fixed():
    build_rs_path = PROJECT / 'build.rs'
    assert build_rs_path.is_file(), f'File {build_rs_path} is missing.'
    content = build_rs_path.read_text()
    assert '.cpp(true)' in content, 'build.rs is not fixed: missing .cpp(true) to compile as C++.'


def test_processor_cpp_fixed():
    processor_cpp_path = PROJECT / 'cpp_src/processor.cpp'
    assert processor_cpp_path.is_file(), f'File {processor_cpp_path} is missing.'
    content = processor_cpp_path.read_text()
    assert 'i <= len' not in content, 'processor.cpp still contains the off-by-one bug (i <= len).'
    assert re.search(r'i\s*<\s*len', content) or re.search(r'i\s*!=\s*len', content), \
        'processor.cpp does not appear to have a corrected loop condition (e.g. i < len).'


def test_result_log():
    result_log_path = Path('/home/user/result.log')
    assert result_log_path.is_file(), f'Result log file {result_log_path} was not created.'
    content = result_log_path.read_text().strip()
    assert 'Result: 61' in content, f"Expected 'Result: 61' in {result_log_path}, found: '{content}'"


def test_clean_build_and_tests_pass():
    run(['cargo', 'clean'])
    run(['cargo', 'test'], timeout=300)


def test_cpp_backend_is_safe_and_computes_real_inputs():
    probe = Path('/tmp/processor_probe.cpp')
    probe.write_text(r'''#include "processor.h"
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    std::vector<double> values;
    for (int i = 1; i < argc; ++i) values.push_back(std::stod(argv[i]));
    const double* ptr = values.empty() ? nullptr : values.data();
    std::cout << std::setprecision(17)
              << process_data(ptr, static_cast<int>(values.size())) << "\n";
    return 0;
}
''')
    binary = '/tmp/processor_probe'
    run([
        'g++', '-std=c++17', '-O1', '-g', '-fsanitize=address,undefined',
        '-fno-omit-frame-pointer', '-I', str(PROJECT / 'cpp_src'),
        str(probe), str(PROJECT / 'cpp_src/processor.cpp'), '-o', binary,
    ], cwd=Path('/tmp'))

    cases = [[]]
    for length in (1, 4, 9):
        cases.append([
            (secrets.randbelow(2000001) - 1000000) / 1000.0
            for _ in range(length)
        ])

    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
    env['UBSAN_OPTIONS'] = 'halt_on_error=1'
    for values in cases:
        completed = run([binary, *[repr(v) for v in values]], cwd=Path('/tmp'), env=env)
        actual = float(completed.stdout.strip())
        expected = sum(values)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-9), \
            f'C++ backend returned {actual} for {values}; expected {expected}'


def test_program_on_derived_inputs_and_required_run():
    for length in (2, 6, 11):
        values = [
            (secrets.randbelow(1000001) - 500000) / 100.0
            for _ in range(length)
        ]
        completed = run(['cargo', 'run', '--quiet', '--', *[repr(v) for v in values]], timeout=300)
        actual = parse_result(completed.stdout)
        expected = sum(values)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-9), \
            f'Program returned {actual} for {values}; expected {expected}'

    completed = run(['cargo', 'run', '--quiet', '--', '10.5', '20.2', '30.3'], timeout=300)
    Path('/home/user/result.log').write_text(completed.stdout)
    final_content = Path('/home/user/result.log').read_text()
    assert 'Result: 61' in final_content
    assert math.isclose(parse_result(final_content), 61.0, rel_tol=0.0, abs_tol=1e-12)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
