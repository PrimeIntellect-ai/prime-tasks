#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
from pathlib import Path

import pytest
from scapy.all import Raw, UDP, rdpcap

CPP_PATH = Path('/home/user/newton_solver.cpp')
LOG_PATH = Path('/home/user/results.log')
PCAP_PATH = Path('/home/user/traffic.pcap')
BINARY_PATH = Path('/tmp/verified_newton_solver')


def extract_guesses():
    guesses = []
    for packet in rdpcap(str(PCAP_PATH)):
        if UDP in packet and packet[UDP].dport == 8080 and Raw in packet:
            guesses.append(bytes(packet[Raw].load).decode('ascii').strip())
    return guesses


def oracle(guess_text):
    x = float(guess_text)
    iterations = 0
    while abs(x*x*x - x) > 1e-6 and iterations < 50:
        derivative = 3*x*x - 1
        if abs(derivative) < 1e-6:
            return ('FAILED', None)
        x = x - (x*x*x - x) / derivative
        iterations += 1
    if iterations >= 50 or not math.isfinite(x):
        return ('FAILED', None)
    return ('CONVERGED', x)


def run_solver(argument, binary=BINARY_PATH):
    completed = subprocess.run(
        [str(binary), str(argument)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert completed.returncode == 0, (
        f'Solver exited with {completed.returncode} for {argument}. '
        f'stderr: {completed.stderr}'
    )
    return completed.stdout.strip()


def assert_correct_output(argument, output):
    status, expected_value = oracle(str(argument))
    if status == 'FAILED':
        assert output == 'FAILED', f'Expected FAILED for {argument}, got {output!r}'
        return

    match = re.fullmatch(r'CONVERGED:\s*([^\s]+)', output)
    assert match, f'Expected a CONVERGED result for {argument}, got {output!r}'
    try:
        actual_value = float(match.group(1))
    except ValueError:
        pytest.fail(f'Invalid converged value in output: {output!r}')
    assert math.isfinite(actual_value)
    assert math.isclose(actual_value, expected_value, rel_tol=1e-5, abs_tol=1e-5), (
        f'Incorrect root for {argument}: expected approximately {expected_value}, '
        f'got {actual_value}'
    )


@pytest.fixture(scope='session', autouse=True)
def compiled_solver():
    assert CPP_PATH.is_file(), f'Missing required file: {CPP_PATH}'
    completed = subprocess.run(
        ['g++', '-std=c++17', '-O0', '-Wall', '-Wextra', str(CPP_PATH), '-o', str(BINARY_PATH)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert completed.returncode == 0, f'newton_solver.cpp does not compile:\n{completed.stderr}'
    yield


def test_results_log_exists():
    """Verify that results.log was created."""
    assert LOG_PATH.is_file(), f'Missing required file: {LOG_PATH}'


def test_results_log_content():
    """Verify results for every UDP/8080 payload, in capture order."""
    with LOG_PATH.open('r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 4, f'Expected at least 4 lines in results.log, found {len(lines)}'

    # Preserve the original fixed-capture assertions, correcting the -0.5 result.
    expected_lines = [
        r'GUESS:\s*2\.0\s*RESULT:\s*CONVERGED:\s*1',
        r'GUESS:\s*0\.577350269\s*RESULT:\s*FAILED',
        r'GUESS:\s*-0\.5\s*RESULT:\s*CONVERGED:\s*1',
        r'GUESS:\s*1\.0\s*RESULT:\s*CONVERGED:\s*1',
    ]
    for i, expected_pattern in enumerate(expected_lines):
        assert re.search(expected_pattern, lines[i]), (
            f"Line {i+1} does not match expected pattern {expected_pattern!r}. Got: {lines[i]!r}"
        )

    guesses = extract_guesses()
    assert guesses, 'No UDP port 8080 payloads were extracted from traffic.pcap'
    assert len(lines) == len(guesses), (
        f'Expected exactly {len(guesses)} result lines, found {len(lines)}'
    )

    for line, guess in zip(lines, guesses):
        prefix = f'GUESS: {guess} RESULT: '
        assert line.startswith(prefix), f'Expected line to start with {prefix!r}, got {line!r}'
        recorded_output = line[len(prefix):]
        actual_output = run_solver(guess)
        assert recorded_output == actual_output, (
            f'results.log does not contain the program output for guess {guess}: '
            f'logged {recorded_output!r}, program produced {actual_output!r}'
        )
        assert_correct_output(guess, actual_output)


def test_cpp_code_fixed():
    """Preserve the original source assertions."""
    assert CPP_PATH.is_file(), f'Missing required file: {CPP_PATH}'
    code = CPP_PATH.read_text()
    assert 'iter <= MAX_ITER' not in code, (
        'The off-by-one bug (iter <= MAX_ITER) was not fixed in the while loop condition.'
    )
    assert '1e-6' in code, (
        "Could not find the threshold '1e-6' used to check the derivative in newton_solver.cpp."
    )


def test_derivative_guard_is_behavioral():
    """Exercise several non-capture inputs whose derivatives are inside the forbidden range."""
    critical = 1.0 / math.sqrt(3.0)
    probes = [critical, -critical, critical + 1e-8, -critical - 1e-8]
    for probe in probes:
        assert abs(3*probe*probe - 1) < 1e-6
        output = run_solver(format(probe, '.17g'))
        assert output == 'FAILED', (
            f'Solver did not gracefully abort for near-zero derivative at {probe}: {output!r}'
        )


def test_iteration_boundary_with_sanitizer():
    """Exercise the array boundary with a reduced iteration limit when the supplied macro is present."""
    code = CPP_PATH.read_text()
    pattern = re.compile(r'^\s*#\s*define\s+MAX_ITER\s+50\b.*$', re.MULTILINE)
    if not pattern.search(code):
        pytest.skip('MAX_ITER is no longer defined by the original macro form')

    reduced = pattern.sub('#define MAX_ITER 1', code, count=1)
    reduced_source = Path('/tmp/newton_solver_boundary.cpp')
    reduced_binary = Path('/tmp/newton_solver_boundary')
    reduced_source.write_text(reduced)

    compiled = subprocess.run(
        [
            'g++', '-std=c++17', '-O0', '-g',
            '-fsanitize=address,undefined', '-fno-sanitize-recover=all',
            str(reduced_source), '-o', str(reduced_binary),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert compiled.returncode == 0, f'Boundary-check build failed:\n{compiled.stderr}'

    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
    completed = subprocess.run(
        [str(reduced_binary), '2.0'],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        env=env,
    )
    assert completed.returncode == 0, (
        'The iteration boundary caused a sanitizer failure, indicating an out-of-bounds access.\n'
        + completed.stderr
    )
    assert completed.stdout.strip() == 'FAILED'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
