#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from pathlib import Path

SOURCE_PATH = Path('/home/user/policy_scanner.cpp')
EXECUTABLE_PATH = Path('/home/user/policy_scanner')
RESULTS_PATH = Path('/home/user/scan_results.txt')
SOURCE_DATA_PATH = Path('/home/user/audit_data/source_code.txt')
AUTH_DATA_PATH = Path('/home/user/audit_data/auth.log')


def read_results():
    assert RESULTS_PATH.is_file(), f'The results file {RESULTS_PATH} does not exist. Did you run the program?'
    with RESULTS_PATH.open('r') as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def run_scanner(executable):
    RESULTS_PATH.unlink(missing_ok=True)
    completed = subprocess.run(
        [str(executable)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f'{executable} exited with status {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    return read_results()


def expected_report(source_text, auth_text):
    source_lines = source_text.splitlines()
    sql_findings = []
    xss_findings = []

    for line_number, line in enumerate(source_lines, 1):
        if '+' in line and re.search(r'\bSELECT\b.*\bWHERE\b', line):
            sql_findings.append(f'VULN: SQLi found on line {line_number}')
        if '+' in line and re.search(r'<[A-Za-z0-9]+>', line):
            xss_findings.append(f'VULN: XSS found on line {line_number}')

    counts = {}
    first_seen = []
    for line in auth_text.splitlines():
        match = re.fullmatch(r'\s*(\S+)\s+-\s+FAILED LOGIN\s*', line)
        if match:
            ip = match.group(1)
            if ip not in counts:
                counts[ip] = 0
                first_seen.append(ip)
            counts[ip] += 1

    alerts = [
        f'ALERT: Brute force detected from {ip}'
        for ip in first_seen
        if counts[ip] > 3
    ]
    return sql_findings + xss_findings + alerts


def test_policy_scanner_cpp_exists():
    assert os.path.isfile('/home/user/policy_scanner.cpp'), 'The source file /home/user/policy_scanner.cpp does not exist.'


def test_policy_scanner_executable_exists():
    executable_path = '/home/user/policy_scanner'
    assert os.path.isfile(executable_path), f'The executable {executable_path} does not exist. Did you compile the code?'
    assert os.access(executable_path, os.X_OK), f'The file {executable_path} is not executable.'
    with open(executable_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'The file {executable_path} is not a compiled executable.'


def test_scan_results_content():
    lines = run_scanner(EXECUTABLE_PATH)

    expected_lines = [
        'VULN: SQLi found on line 2',
        'VULN: XSS found on line 7',
        'ALERT: Brute force detected from 192.168.1.10'
    ]

    assert len(lines) == len(expected_lines), f'Expected {len(expected_lines)} lines in scan_results.txt, but found {len(lines)}.'

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in scan_results.txt is incorrect.\nExpected: '{expected}'\nActual: '{actual}'"


def test_scanner_handles_changed_inputs():
    compiled_from_submission = Path('/tmp/policy_scanner_from_source')
    compilation = subprocess.run(
        ['g++', '-std=c++17', str(SOURCE_PATH), '-o', str(compiled_from_submission)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compilation.returncode == 0, (
        'policy_scanner.cpp does not compile with g++ -std=c++17.\n'
        f'stdout:\n{compilation.stdout}\nstderr:\n{compilation.stderr}'
    )

    rng = random.SystemRandom()
    flagged_ip = f'10.{rng.randint(1, 220)}.{rng.randint(1, 220)}.{rng.randint(1, 220)}'
    other_ip = f'172.{rng.randint(16, 31)}.{rng.randint(1, 220)}.{rng.randint(1, 220)}'
    padding = ['// harmless padding'] * rng.randint(1, 5)

    cases = [
        (
            '\n'.join(padding + [
                'int total = left + right;',
                'auto prepared = "SELECT id FROM accounts WHERE id = ?";',
                'auto backwards = "WHERE x SELECT" + value;',
                'auto query = "SELECT token FROM sessions WHERE owner = \'" + username + "\'";',
                'auto safe_html = "<div>constant</div>";',
                'auto page = "<section>Account</section>" + username;',
                'auto title = "<H2>Title</H2>" + display_name;',
            ]) + '\n',
            '\n'.join([
                f'{flagged_ip} - FAILED LOGIN',
                f'{other_ip} - FAILED LOGIN',
                f'{flagged_ip} - FAILED LOGIN',
                f'{other_ip} - SUCCESS LOGIN',
                f'{flagged_ip} - FAILED LOGIN',
                f'{other_ip} - FAILED LOGIN',
                f'{flagged_ip} - FAILED LOGIN',
                f'{flagged_ip} - FAILED LOGIN',
                f'{other_ip} - FAILED LOGIN',
            ]) + '\n',
        ),
        (
            '\n'.join([
                '// no findings in this input',
                'auto q = "SELECT value FROM table WHERE id = ?";',
                'auto markup = "<div>fixed text</div>";',
                'int sum = first + second;',
                'auto wrong_order = "WHERE before SELECT" + name;',
            ]) + '\n',
            '\n'.join([
                f'{flagged_ip} - FAILED LOGIN',
                f'{flagged_ip} - FAILED LOGIN',
                f'{flagged_ip} - FAILED LOGIN',
                f'{other_ip} - SUCCESS LOGIN',
            ]) + '\n',
        ),
    ]

    original_source_data = SOURCE_DATA_PATH.read_bytes()
    original_auth_data = AUTH_DATA_PATH.read_bytes()
    try:
        for source_text, auth_text in cases:
            SOURCE_DATA_PATH.write_text(source_text)
            AUTH_DATA_PATH.write_text(auth_text)
            expected = expected_report(source_text, auth_text)

            for executable in (EXECUTABLE_PATH, compiled_from_submission):
                actual = run_scanner(executable)
                assert actual == expected, (
                    f'{executable} produced an incorrect report for changed inputs.\n'
                    f'Expected: {expected!r}\nActual: {actual!r}'
                )
    finally:
        SOURCE_DATA_PATH.write_bytes(original_source_data)
        AUTH_DATA_PATH.write_bytes(original_auth_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
