#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import secrets
import subprocess
import tempfile
from collections import Counter

import pytest

COMPRESSOR = '/home/user/rle_compress.py'
ARCHIVE = '/home/user/archive.rle'
VERIFIER = '/home/user/verify.py'
DECOMPRESSED = '/home/user/decompressed.txt'

EXPECTED_LINES = [
    "[INFO] Application started\n",
    "[INFO] Application started\n",
    "[WARN] High memory usage\n",
    "[WARN] High memory usage\n",
    "[WARN] High memory usage\n",
    "[INFO] User login\n",
    "[INFO] User login\n",
    "[ERROR] Connection timeout\n",
    "[ERROR] Connection timeout\n",
    "[INFO] Job finished\n",
    "[INFO] Job finished\n",
    "[INFO] Job finished\n",
]

EXPECTED_RECORDS = Counter([
    (2, '[INFO] Application started\n'),
    (3, '[WARN] High memory usage\n'),
    (2, '[INFO] User login\n'),
    (2, '[ERROR] Connection timeout\n'),
    (3, '[INFO] Job finished\n'),
])


def run_compressor(input_text, output_path, timeout=15):
    return subprocess.run(
        ['python3', COMPRESSOR, output_path],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def encode(lines):
    if not lines:
        return ''
    output = []
    previous = lines[0]
    count = 1
    for line in lines[1:]:
        if line == previous:
            count += 1
        else:
            output.append(f'{count}|{previous}')
            previous = line
            count = 1
    output.append(f'{count}|{previous}')
    return ''.join(output)


def test_files_exist():
    expected_files = [COMPRESSOR, ARCHIVE, VERIFIER, DECOMPRESSED]
    for filepath in expected_files:
        assert os.path.exists(filepath), f"File {filepath} is missing."


def test_compressor_uses_flock():
    assert os.path.isfile(COMPRESSOR), f"{COMPRESSOR} does not exist."
    with open(COMPRESSOR, 'r') as f:
        code = f.read()
    assert 'fcntl' in code, "The compressor script must import and use fcntl."
    assert 'flock' in code, "The compressor script must use fcntl.flock."
    compile(code, COMPRESSOR, 'exec')


def test_decompressed_content():
    assert os.path.isfile(DECOMPRESSED), f"{DECOMPRESSED} does not exist."
    with open(DECOMPRESSED, 'r') as f:
        actual_lines = f.readlines()
    assert sorted(actual_lines) == sorted(EXPECTED_LINES), (
        "The decompressed output does not match the expected filtered logs. "
        "Ensure [DEBUG] lines are removed and counts are correct."
    )


def test_archive_rle_format_and_contents():
    assert os.path.isfile(ARCHIVE), f"{ARCHIVE} does not exist."
    with open(ARCHIVE, 'r') as f:
        lines = f.readlines()
    assert len(lines) > 0, "The archive.rle file is empty."

    records = []
    expanded = []
    for line in lines:
        parts = line.split('|', 1)
        assert len(parts) == 2, f"Invalid RLE format in archive.rle: {line.strip()}"
        count_str, content = parts
        assert count_str.isdigit(), f"RLE count is not a number: {count_str}"
        assert int(count_str) > 0, f"RLE count must be positive: {count_str}"
        assert "[DEBUG]" not in content, f"DEBUG lines should have been filtered out: {content.strip()}"
        records.append((int(count_str), content))
        expanded.extend([content] * int(count_str))

    assert Counter(records) == EXPECTED_RECORDS, "archive.rle is not the RLE output of the three filtered logs"
    assert sorted(expanded) == sorted(EXPECTED_LINES), "archive.rle does not decompress to the required filtered logs"


def test_compressor_on_derived_input_and_append_behavior():
    token = secrets.token_hex(12)
    lines = [
        f'alpha-{token}\n',
        f'alpha-{token}\n',
        f'value|with|pipes-{token}\n',
        f'value|with|pipes-{token}\n',
        f'value|with|pipes-{token}\n',
        '\n',
        f'omega-{token}\n',
    ]
    expected = encode(lines)

    with tempfile.TemporaryDirectory() as td:
        output = os.path.join(td, 'result.rle')
        prefix = f'1|existing-{token}\n'
        with open(output, 'w') as f:
            f.write(prefix)

        result = run_compressor(''.join(lines), output)
        assert result.returncode == 0, result.stderr
        with open(output, 'r') as f:
            actual = f.read()
        assert actual == prefix + expected, "compressor did not append the correct line-based RLE payload"

        empty_result = run_compressor('', output)
        assert empty_result.returncode == 0, empty_result.stderr
        with open(output, 'r') as f:
            assert f.read() == prefix + expected, "empty input must not add records"


def test_compressor_requires_exactly_one_argument():
    no_arg = subprocess.run(
        ['python3', COMPRESSOR],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    two_args = subprocess.run(
        ['python3', COMPRESSOR, '/tmp/rle-extra-1', '/tmp/rle-extra-2'],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert no_arg.returncode != 0, "compressor must reject a missing output argument"
    assert two_args.returncode != 0, "compressor must reject extra arguments"


def test_parallel_compressor_payloads_are_not_interleaved():
    token = secrets.token_hex(10)
    with tempfile.TemporaryDirectory() as td:
        output = os.path.join(td, 'parallel.rle')
        inputs = []
        expected_payloads = []
        for worker in range(3):
            lines = []
            for index in range(5000):
                line = f'worker-{worker}-{token}-{index:05d}-' + ('x' * 80) + '\n'
                lines.extend([line, line])
            text = ''.join(lines)
            input_path = os.path.join(td, f'input-{worker}.txt')
            with open(input_path, 'w') as f:
                f.write(text)
            inputs.append(input_path)
            expected_payloads.append(encode(lines))

        processes = []
        handles = []
        try:
            for input_path in inputs:
                handle = open(input_path, 'r')
                handles.append(handle)
                processes.append(subprocess.Popen(
                    ['python3', COMPRESSOR, output],
                    stdin=handle,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                ))
            for process in processes:
                _, stderr = process.communicate(timeout=30)
                assert process.returncode == 0, stderr
        finally:
            for handle in handles:
                handle.close()
            for process in processes:
                if process.poll() is None:
                    process.kill()

        with open(output, 'r') as f:
            actual = f.read()
        valid_results = {''.join(order) for order in itertools.permutations(expected_payloads)}
        assert actual in valid_results, "parallel compressed payloads were corrupted or interleaved"


def test_verify_script_executes_and_decompresses_derived_archive():
    token = secrets.token_hex(12)
    records = [
        (2, f'first-{token}\n'),
        (1, f'contains|separator-{token}\n'),
        (4, '\n'),
        (3, f'last-{token}\n'),
    ]
    archive_text = ''.join(f'{count}|{content}' for count, content in records)
    expected = ''.join(content * count for count, content in records)

    with open(ARCHIVE, 'rb') as f:
        old_archive = f.read()
    with open(DECOMPRESSED, 'rb') as f:
        old_decompressed = f.read()

    try:
        with open(ARCHIVE, 'w') as f:
            f.write(archive_text)
        with open(DECOMPRESSED, 'w') as f:
            f.write('stale data that must be replaced\n')

        result = subprocess.run(
            ['python3', VERIFIER],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, result.stderr
        with open(DECOMPRESSED, 'r') as f:
            actual = f.read()
        assert actual == expected, "verify.py did not decompress the derived archive correctly"
    finally:
        with open(ARCHIVE, 'wb') as f:
            f.write(old_archive)
        with open(DECOMPRESSED, 'wb') as f:
            f.write(old_decompressed)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
