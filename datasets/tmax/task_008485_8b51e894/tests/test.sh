#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
from collections import defaultdict
from pathlib import Path

BASE = Path('/home/user/util_dev')
SOURCE = BASE / 'fast_parser.c'
RUNNER = BASE / 'test_runner.sh'
LEGACY = BASE / 'legacy_parser.py'


def reference_output(log_text):
    counts = defaultdict(int)
    for line in log_text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 3:
            continue
        _, ip, hex_uri = parts
        try:
            uri = bytes.fromhex(hex_uri).decode('ascii')
        except Exception:
            continue
        if uri.startswith('/api/v1/'):
            counts[ip] += 1
    return sorted(f'{ip} {count}' for ip, count in counts.items() if count > 2)


def run_program(argv, log_text):
    result = subprocess.run(
        argv,
        input=log_text,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Program {argv} exited with {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return sorted(result.stdout.strip().splitlines())


def mixed_case_hex(text, rng, mode):
    encoded = text.encode('ascii').hex()
    if mode == 'lower':
        return encoded
    if mode == 'upper':
        return encoded.upper()
    return ''.join(
        ch.upper() if ch in 'abcdef' and rng.randrange(2) else ch
        for ch in encoded
    )


def test_test_runner_exists():
    assert RUNNER.is_file(), f'{RUNNER} does not exist'


def test_test_runner_execution_and_outputs():
    for name in ('fast_parser', 'test_log.txt', 'py_out.txt', 'c_out.txt', 'diff_output.txt'):
        path = BASE / name
        if path.exists():
            path.unlink()

    result = subprocess.run(
        ['bash', 'test_runner.sh'],
        cwd=BASE,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'test_runner.sh failed with exit code {result.returncode}:\n{result.stderr}'
    )

    log_path = BASE / 'test_log.txt'
    assert log_path.is_file(), f'{log_path} was not generated'
    lines = log_path.read_text().splitlines()
    assert len(lines) >= 8, f'{log_path} has fewer than 8 lines (found {len(lines)})'

    diff_path = BASE / 'diff_output.txt'
    assert diff_path.is_file(), f'{diff_path} was not generated'
    assert diff_path.stat().st_size == 0, (
        f'{diff_path} is not empty, indicating differences between C and Python outputs'
    )

    binary = BASE / 'fast_parser'
    assert binary.is_file(), f'Compiled executable {binary} not found'
    assert binary.read_bytes()[:4] == b'\x7fELF', 'fast_parser is not a compiled ELF executable'

    py_out_path = BASE / 'py_out.txt'
    c_out_path = BASE / 'c_out.txt'
    assert py_out_path.is_file(), f'{py_out_path} was not generated'
    assert c_out_path.is_file(), f'{c_out_path} was not generated'

    log_text = log_path.read_text()
    actual_py = run_program(['python3', str(LEGACY)], log_text)
    actual_c = run_program([str(binary)], log_text)
    assert py_out_path.read_text().splitlines() == actual_py, 'py_out.txt is not the sorted Python output'
    assert c_out_path.read_text().splitlines() == actual_c, 'c_out.txt is not the sorted C output'
    assert actual_c == actual_py, 'The generated test log does not produce parser parity'

    lowercase_restricted = defaultdict(int)
    for line in lines:
        parts = line.split()
        if len(parts) != 3:
            continue
        _, ip, encoded = parts
        try:
            uri = bytes.fromhex(encoded).decode('ascii')
        except Exception:
            continue
        if uri.startswith('/api/v1/') and any(ch in 'abcdef' for ch in encoded):
            lowercase_restricted[ip] += 1
    assert any(count > 2 for count in lowercase_restricted.values()), (
        'test_log.txt does not expose the original lowercase-hex bug while triggering the rate limit'
    )


def test_fast_parser_fixes_lowercase_hex():
    secret_log = (
        '100 1.1.1.1 2f6170692f76312f\n'
        '101 1.1.1.1 2f6170692f76312f\n'
        '102 1.1.1.1 2f6170692f76312f\n'
    )

    c_parser_path = BASE / 'fast_parser'
    assert c_parser_path.is_file(), f'Compiled executable {c_parser_path} not found'

    c_result = subprocess.run(
        [str(c_parser_path)], input=secret_log, text=True, capture_output=True
    )
    assert c_result.returncode == 0, 'fast_parser execution failed on secret log'

    py_result = subprocess.run(
        ['python3', str(LEGACY)], input=secret_log, text=True, capture_output=True
    )
    assert py_result.returncode == 0, 'legacy_parser.py execution failed on secret log'

    c_out = sorted(c_result.stdout.strip().splitlines())
    py_out = sorted(py_result.stdout.strip().splitlines())
    assert c_out == py_out, (
        f'Outputs differ on lowercase hex input.\nC output: {c_out}\n'
        f'Python output: {py_out}\nThe C parser likely still fails on lowercase hex decoding.'
    )


def test_compiled_source_matches_independent_random_logs(tmp_path):
    assert SOURCE.is_file(), f'{SOURCE} does not exist'
    binary = tmp_path / 'fast_parser_checked'
    compiled = subprocess.run(
        ['gcc', '-o', str(binary), str(SOURCE)],
        cwd=BASE,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f'fast_parser.c did not compile:\n{compiled.stderr}'
    assert binary.read_bytes()[:4] == b'\x7fELF', 'gcc output is not an ELF executable'

    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    restricted_paths = ['/api/v1/', '/api/v1/data', '/api/v1/users', '/api/v1/x/y']
    other_paths = ['/api/v1', '/api/v2/data', '/API/v1/data', '/other', 'api/v1/data']

    for trial in range(12):
        address_count = rng.randint(4, 9)
        addresses = [
            f'10.{rng.randrange(1, 255)}.{trial}.{rng.randrange(1, 255)}'
            for _ in range(address_count)
        ]
        restricted_counts = [rng.randint(3, 7), rng.randint(3, 7), rng.randint(0, 2)]
        restricted_counts.extend(rng.randint(0, 6) for _ in range(address_count - 3))

        lines = []
        timestamp = rng.randrange(100000, 900000)
        case_index = 0
        for ip, restricted_count in zip(addresses, restricted_counts):
            for _ in range(restricted_count):
                path = rng.choice(restricted_paths) + str(rng.randrange(10000))
                mode = ('lower', 'upper', 'mixed')[case_index % 3]
                lines.append(f'{timestamp} {ip} {mixed_case_hex(path, rng, mode)}')
                timestamp += rng.randrange(1, 20)
                case_index += 1
            for _ in range(rng.randint(1, 4)):
                path = rng.choice(other_paths) + str(rng.randrange(10000))
                mode = ('mixed', 'upper', 'lower')[case_index % 3]
                lines.append(f'{timestamp} {ip} {mixed_case_hex(path, rng, mode)}')
                timestamp += rng.randrange(1, 20)
                case_index += 1

        rng.shuffle(lines)
        log_text = '\n'.join(lines) + '\n'
        expected = reference_output(log_text)
        assert expected, 'Generated verification case unexpectedly has no violators'

        c_output = run_program([str(binary)], log_text)
        assert c_output == expected, (
            f'C parser disagrees with the independent model on randomized trial {trial}.\n'
            f'Expected: {expected}\nActual: {c_output}'
        )

        legacy_output = run_program(['python3', str(LEGACY)], log_text)
        assert legacy_output == expected, 'legacy_parser.py was modified or no longer matches its specified behavior'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
