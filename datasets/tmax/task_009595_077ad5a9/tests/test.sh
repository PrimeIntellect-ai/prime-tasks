#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import shlex
import shutil
import string
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/api_gateway')
EXE = PROJECT / 'gateway_tool'
LOG = Path('/home/user/gateway_test_results.log')
RUNNER = PROJECT / 'run_tests.py'


def fletcher16(data):
    sum1 = 0
    sum2 = 0
    for byte in data:
        sum1 = (sum1 + byte) % 255
        sum2 = (sum2 + sum1) % 255
    return (sum2 << 8) | sum1


def run_runner():
    return subprocess.run(
        ['python3', str(RUNNER)],
        cwd=str(PROJECT),
        capture_output=True,
        text=True,
        timeout=20,
    )


def read_nonempty_log_lines():
    assert LOG.is_file(), f'Log file {LOG} was not generated.'
    with LOG.open() as handle:
        return [line.strip() for line in handle if line.strip()]


def test_makefile_fixed_and_builds():
    makefile_path = PROJECT / 'Makefile'
    assert makefile_path.is_file(), f'{makefile_path} does not exist.'

    content = makefile_path.read_text()
    assert 'rate_limit.o' in content, 'rate_limit.o is missing from the Makefile.'

    lines = content.split('\n')
    linking_line = ''
    for i, line in enumerate(lines):
        if line.startswith('gateway_tool:'):
            if i + 1 < len(lines):
                linking_line = lines[i + 1]
            break
    assert 'rate_limit.o' in linking_line, 'Makefile linking step does not include rate_limit.o'

    clean = subprocess.run(['make', 'clean'], cwd=PROJECT, capture_output=True, text=True, timeout=30)
    assert clean.returncode == 0, f'make clean failed:\n{clean.stdout}\n{clean.stderr}'
    build = subprocess.run(['make'], cwd=PROJECT, capture_output=True, text=True, timeout=30)
    assert build.returncode == 0, f'make failed:\n{build.stdout}\n{build.stderr}'


def test_gateway_tool_compiled():
    assert EXE.is_file(), f'Executable {EXE} not found. Did the build succeed?'
    assert os.access(EXE, os.X_OK), f'{EXE} is not executable.'
    with EXE.open('rb') as handle:
        assert handle.read(4) == b'\x7fELF', 'gateway_tool is not a compiled ELF executable.'


def test_cpp_checksum_and_rate_limiter_implementations(tmp_path):
    checksum_driver = tmp_path / 'checksum_driver.cpp'
    checksum_driver.write_text(r'''#include <cstdint>
#include <iostream>
#include <string>
#include "checksum.h"

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::string hex = argv[1];
    if (hex.size() % 2 != 0) return 3;
    std::string data;
    for (std::size_t i = 0; i < hex.size(); i += 2) {
        unsigned int value = std::stoul(hex.substr(i, 2), nullptr, 16);
        data.push_back(static_cast<char>(value));
    }
    std::cout << calculate_fletcher16(data);
    return 0;
}
''')
    checksum_bin = tmp_path / 'checksum_driver'
    compile_checksum = subprocess.run([
        'g++', '-std=c++17', '-Wall', '-Wextra', '-I', str(PROJECT),
        str(checksum_driver), str(PROJECT / 'checksum.cpp'), '-o', str(checksum_bin)
    ], capture_output=True, text=True, timeout=30)
    assert compile_checksum.returncode == 0, (
        'checksum.cpp did not compile with a direct caller:\n'
        + compile_checksum.stdout + compile_checksum.stderr
    )

    rng = secrets.SystemRandom()
    samples = [b'', b'payload_A', bytes(range(256)), b'\x00\xff\x80\x01']
    for _ in range(30):
        samples.append(bytes(rng.randrange(256) for _ in range(rng.randrange(1, 100))))
    for data in samples:
        result = subprocess.run([str(checksum_bin), data.hex()], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == str(fletcher16(data)), (
            f'Wrong Fletcher-16 result for input {data.hex()}'
        )

    rate_driver = tmp_path / 'rate_driver.cpp'
    rate_driver.write_text(r'''#include <iostream>
#include <string>
#include "rate_limit.h"

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    RateLimiter limiter(std::stoi(argv[1]));
    for (int i = 2; i < argc; ++i) {
        std::cout << (limiter.allow_request(argv[i]) ? '1' : '0');
    }
    return 0;
}
''')
    rate_bin = tmp_path / 'rate_driver'
    compile_rate = subprocess.run([
        'g++', '-std=c++17', '-Wall', '-Wextra', '-I', str(PROJECT),
        str(rate_driver), str(PROJECT / 'rate_limit.cpp'), '-o', str(rate_bin)
    ], capture_output=True, text=True, timeout=30)
    assert compile_rate.returncode == 0, (
        'rate_limit.cpp did not compile with a direct caller:\n'
        + compile_rate.stdout + compile_rate.stderr
    )

    alphabet = string.ascii_letters + string.digits + '.:'
    for limit in [0, 1, 2, 3, 5]:
        ips = ['ip-' + ''.join(rng.choice(alphabet) for _ in range(16)) for _ in range(4)]
        sequence = [ips[0], ips[1], ips[0], ips[2], ips[0], ips[1], ips[0], ips[3], ips[1]]
        counts = {}
        expected = []
        for ip in sequence:
            count = counts.get(ip, 0)
            if count < limit:
                expected.append('1')
                counts[ip] = count + 1
            else:
                expected.append('0')
        result = subprocess.run(
            [str(rate_bin), str(limit), *sequence], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout == ''.join(expected), f'RateLimiter failed for max_requests={limit}'


def test_gateway_checksum_logic_on_derived_inputs():
    rng = secrets.SystemRandom()
    cases = ['payload_A', 'gateway', 'x', ''.join(rng.choice(string.ascii_letters) for _ in range(31))]
    for index, data in enumerate(cases):
        checksum = fletcher16(data.encode())
        ip = f'198.51.100.{index + 10}'
        valid = subprocess.run(
            [str(EXE), ip, data, str(checksum)], capture_output=True, text=True, timeout=5
        )
        assert valid.returncode == 0
        assert valid.stdout == 'ALLOWED\n', f'Expected ALLOWED, got {valid.stdout!r}'

        invalid_checksum = checksum ^ 1
        invalid = subprocess.run(
            [str(EXE), ip, data, str(invalid_checksum)], capture_output=True, text=True, timeout=5
        )
        assert invalid.returncode == 0
        assert invalid.stdout == 'CHECKSUM_FAILED\n', f'Expected CHECKSUM_FAILED, got {invalid.stdout!r}'

    res_valid = subprocess.run(
        [str(EXE), '192.168.1.1', 'payload_A', '16223'], capture_output=True, text=True
    )
    assert 'ALLOWED' in res_valid.stdout, f'Expected ALLOWED for valid checksum, got: {res_valid.stdout}'
    res_invalid = subprocess.run(
        [str(EXE), '192.168.1.2', 'payload_A', '9999'], capture_output=True, text=True
    )
    assert 'CHECKSUM_FAILED' in res_invalid.stdout, f'Expected CHECKSUM_FAILED for invalid checksum, got: {res_invalid.stdout}'


def test_run_tests_exists_uses_subprocess_and_executes_required_requests(tmp_path):
    assert RUNNER.is_file(), f'{RUNNER} does not exist.'
    source = RUNNER.read_text()
    tree = ast.parse(source, filename=str(RUNNER))
    module_aliases = set()
    imported_calls = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'subprocess':
                    module_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module == 'subprocess':
            for alias in node.names:
                imported_calls.add(alias.asname or alias.name)
    uses_subprocess_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
            if node.func.value.id in module_aliases:
                uses_subprocess_call = True
        elif isinstance(node.func, ast.Name) and node.func.id in imported_calls:
            uses_subprocess_call = True
    assert uses_subprocess_call, 'run_tests.py must execute gateway_tool using the subprocess module.'

    if LOG.exists():
        LOG.unlink()
    real_run = run_runner()
    assert real_run.returncode == 0, f'run_tests.py failed:\n{real_run.stdout}\n{real_run.stderr}'
    real_lines = read_nonempty_log_lines()
    assert real_lines == ['ALLOWED', 'CHECKSUM_FAILED', 'ALLOWED', 'ALLOWED', 'ALLOWED'], (
        f'Unexpected results from run_tests.py with the compiled gateway_tool: {real_lines}'
    )

    saved_exe = tmp_path / 'gateway_tool.real'
    shutil.copy2(EXE, saved_exe)
    trace = tmp_path / 'gateway_invocations.tsv'
    wrapper = f'''#!/bin/sh
printf '%s\\t%s\\t%s\\n' "$1" "$2" "$3" >> {shlex.quote(str(trace))}
case "$1|$2|$3" in
  '10.0.0.1|payload_A|16223') printf 'RATE_LIMITED\\n' ;;
  '10.0.0.1|payload_B|99999') printf 'ALLOWED\\n' ;;
  '10.0.0.1|payload_C|17513') printf 'CHECKSUM_FAILED\\n' ;;
  '10.0.0.1|payload_D|17772') printf 'RATE_LIMITED\\n' ;;
  '10.0.0.1|payload_E|18031') printf 'CHECKSUM_FAILED\\n' ;;
  *) printf 'ALLOWED\\n' ;;
esac
'''
    expected_calls = [
        ('10.0.0.1', 'payload_A', '16223'),
        ('10.0.0.1', 'payload_B', '99999'),
        ('10.0.0.1', 'payload_C', '17513'),
        ('10.0.0.1', 'payload_D', '17772'),
        ('10.0.0.1', 'payload_E', '18031'),
    ]
    dynamic_outputs = ['RATE_LIMITED', 'ALLOWED', 'CHECKSUM_FAILED', 'RATE_LIMITED', 'CHECKSUM_FAILED']
    try:
        EXE.write_text(wrapper)
        EXE.chmod(0o755)
        if LOG.exists():
            LOG.unlink()
        instrumented = run_runner()
        assert instrumented.returncode == 0, (
            f'run_tests.py failed while executing the instrumented gateway_tool:\n'
            f'{instrumented.stdout}\n{instrumented.stderr}'
        )
        assert trace.is_file(), 'run_tests.py did not execute ./gateway_tool.'
        calls = [tuple(line.split('\t')) for line in trace.read_text().splitlines()]
        assert calls == expected_calls, f'run_tests.py made the wrong calls or used the wrong order: {calls}'
        assert read_nonempty_log_lines() == dynamic_outputs, (
            'run_tests.py did not append the stripped stdout returned by each gateway_tool invocation.'
        )
    finally:
        shutil.copy2(saved_exe, EXE)
        EXE.chmod(0o755)

    if LOG.exists():
        LOG.unlink()
    final_run = run_runner()
    assert final_run.returncode == 0, f'run_tests.py failed after restoring gateway_tool: {final_run.stderr}'


def test_log_file_contents():
    lines = read_nonempty_log_lines()
    assert len(lines) == 5, f'Expected exactly 5 lines in the log file, but found {len(lines)}.'
    assert lines[0] == 'ALLOWED', f'Line 1 expected ALLOWED, got {lines[0]}'
    assert lines[1] == 'CHECKSUM_FAILED', f'Line 2 expected CHECKSUM_FAILED, got {lines[1]}'
    assert lines[2] == 'ALLOWED', f'Line 3 expected ALLOWED, got {lines[2]}'
    assert lines[3] == 'ALLOWED', f'Line 4 expected ALLOWED, got {lines[3]}'
    assert lines[4] in ['ALLOWED', 'RATE_LIMITED'], f'Line 5 expected ALLOWED or RATE_LIMITED, got {lines[4]}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
