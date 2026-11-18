#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/project')
SOURCE = PROJECT / 'src/mapper.c'
ROUTES = PROJECT / 'data/routes.txt'
EXPECTED_ROUTES = (
    '/api/v1/users/{id} -> GetUser\n'
    '/api/v1/products/{id} -> GetProduct\n'
    '/api/v1/orders/{category}/{id}/status -> CheckOrderStatus\n'
)


def test_directories_exist():
    """Verify that the required directories exist."""
    dirs = [
        '/home/user/project/src',
        '/home/user/project/data',
        '/home/user/project/build'
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} is missing."


def test_routes_file_moved():
    """Verify that routes.txt was moved intact to the data directory."""
    assert not os.path.exists('/home/user/project/routes.txt'), "routes.txt should have been moved from /home/user/project/."
    assert os.path.isfile('/home/user/project/data/routes.txt'), "routes.txt is missing in /home/user/project/data/."
    assert ROUTES.read_text() == EXPECTED_ROUTES, "The moved routes.txt file was modified or truncated."


def test_mapper_source_exists():
    """Verify that mapper.c was created."""
    assert os.path.isfile('/home/user/project/src/mapper.c'), "mapper.c source file is missing."


def test_binaries_exist_and_executable():
    """Verify that the compiled binaries exist, are executable, and are native binaries."""
    binaries = [
        '/home/user/project/build/mapper_prod',
        '/home/user/project/build/mapper_test'
    ]
    for b in binaries:
        assert os.path.isfile(b), f"Binary {b} is missing."
        assert os.access(b, os.X_OK), f"Binary {b} is not executable."
        with open(b, 'rb') as f:
            assert f.read(4) == b'\x7fELF', f"Binary {b} is not a compiled ELF executable."


def compute_expected_output(routes_file_path, seed):
    """Helper to compute the expected output given the routes file and a seed."""
    expected_lines = []
    with open(routes_file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('->')
            if len(parts) == 2:
                url = parts[0].strip()
                method = parts[1].strip()
                stripped_url = re.sub(r'\{[^}]*\}', '', url)
                sum_url = sum(ord(c) for c in stripped_url)
                sum_method = sum(ord(c) for c in method)
                checksum = (sum_url * sum_method) % seed
                expected_lines.append(f"Checksum: {checksum} | Method: {method}")
    return expected_lines


def test_output_prod_log():
    """Verify the contents of output_prod.log."""
    log_path = '/home/user/project/build/output_prod.log'
    routes_path = '/home/user/project/data/routes.txt'
    assert os.path.isfile(log_path), f"Output log {log_path} is missing."
    expected_lines = compute_expected_output(routes_path, 17)
    with open(log_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, f"Contents of {log_path} do not match the expected checksums and format."


def test_output_test_log():
    """Verify the contents of output_test.log."""
    log_path = '/home/user/project/build/output_test.log'
    routes_path = '/home/user/project/data/routes.txt'
    assert os.path.isfile(log_path), f"Output log {log_path} is missing."
    expected_lines = compute_expected_output(routes_path, 31)
    with open(log_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, f"Contents of {log_path} do not match the expected checksums and format."


def _random_word(length=14):
    alphabet = string.ascii_letters
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def _exercise(binary, seed, workdir, label):
    token = _random_word()
    method1 = _random_word()
    method2 = _random_word()
    method3 = _random_word()
    input_path = workdir / f'{label}_routes.txt'
    output_path = workdir / f'{label}_output.log'
    input_path.write_text(
        f'/hidden/{token}/{{user_id}}/tail/{{part}} -> {method1}\n'
        f'/plain/{token}/endpoint -> {method2}\n'
        f'/many/{{first}}/{token}/{{second}}/done -> {method3}\n'
    )
    expected = compute_expected_output(input_path, seed)
    result = subprocess.run(
        [str(binary), str(input_path), str(output_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"{binary} failed on a verifier-generated input: {result.stderr}"
    assert output_path.is_file(), f"{binary} did not create the requested output file."
    assert output_path.read_text().splitlines() == expected, f"{binary} produced incorrect dynamic output for SEED={seed}."


def test_submitted_binaries_execute_correctly(tmp_path):
    """Execute both submitted binaries on unpredictable verifier-generated routes."""
    _exercise(PROJECT / 'build/mapper_prod', 17, tmp_path, 'submitted_prod')
    _exercise(PROJECT / 'build/mapper_test', 31, tmp_path, 'submitted_test')


def test_mapper_source_builds_and_implements_algorithm(tmp_path):
    """Compile mapper.c independently with both seeds and exercise the resulting programs."""
    for seed in (17, 31):
        binary = tmp_path / f'rebuilt_{seed}'
        result = subprocess.run(
            ['gcc', '-std=c11', '-O2', f'-DSEED={seed}', str(SOURCE), '-o', str(binary)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"mapper.c failed to compile with SEED={seed}: {result.stderr}"
        _exercise(binary, seed, tmp_path, f'rebuilt_seed_{seed}')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
