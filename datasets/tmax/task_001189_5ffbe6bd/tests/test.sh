#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
RAW = HOME / 'raw_data'
CLEAN = HOME / 'clean_data'
SUMMARY = HOME / 'summary.txt'
BINARY = Path('/tmp/cleaner_verify')

ORIGINAL_INPUTS = {
    'alpha/log1.win1252.txt': bytes.fromhex('54 65 6d 70 65 72 61 74 75 72 65 3a 20 32 35 b0 43'),
    'alpha/log2.utf8.txt': bytes.fromhex('53 74 61 74 75 73 3a 20 4f 4b 20 e2 9c 93'),
    'beta/nested/log3.utf16le.txt': bytes.fromhex('57 00 61 00 72 00 6e 00 69 00 6e 00 67 00 3a 00 20 00 0a 00 4c 00 6f 00 77 00 20 00 62 00 61 00 74 00 74 00 65 00 72 00 79 00'),
}

ORIGINAL_OUTPUTS = {
    'alpha/log1.txt': 'Temperature: 25°C'.encode('utf-8'),
    'alpha/log2.txt': 'Status: OK ✓'.encode('utf-8'),
    'beta/nested/log3.txt': 'Warning: \nLow battery'.encode('utf-8'),
}


def reset_original_dataset():
    shutil.rmtree(RAW, ignore_errors=True)
    shutil.rmtree(CLEAN, ignore_errors=True)
    if SUMMARY.exists() or SUMMARY.is_symlink():
        SUMMARY.unlink()
    for relative, data in ORIGINAL_INPUTS.items():
        path = RAW / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def run_cleaner():
    subprocess.run([str(BINARY)], cwd=str(HOME), check=True, timeout=30)


def test_00_cleaner_go_exists_and_uses_atomic_writes_and_runs():
    """Verify the source, compile it, and execute it against the original dataset."""
    go_file = '/home/user/cleaner.go'
    assert os.path.isfile(go_file), f'Go source file {go_file} does not exist.'

    with open(go_file, 'r', encoding='utf-8') as f:
        content = f.read()

    assert 'os.Rename' in content or 'Rename' in content, 'The Go program does not appear to use os.Rename for atomic writes.'
    assert 'Temp' in content or '.tmp' in content, 'The Go program does not appear to use temporary files for atomic writes.'

    subprocess.run(
        ['go', 'build', '-o', str(BINARY), 'cleaner.go'],
        cwd=str(HOME), check=True, timeout=60,
    )
    reset_original_dataset()
    run_cleaner()


def test_clean_data_structure_and_content():
    """Verify that the clean_data directory has the correct mirrored structure and UTF-8 files."""
    expected_files = {
        '/home/user/clean_data/alpha/log1.txt': 'Temperature: 25°C'.encode('utf-8'),
        '/home/user/clean_data/alpha/log2.txt': 'Status: OK ✓'.encode('utf-8'),
        '/home/user/clean_data/beta/nested/log3.txt': 'Warning: \nLow battery'.encode('utf-8')
    }

    for filepath, expected_bytes in expected_files.items():
        assert os.path.isfile(filepath), f'Expected converted file {filepath} does not exist.'
        with open(filepath, 'rb') as f:
            content = f.read()
        assert content == expected_bytes, f'Content of {filepath} does not match expected UTF-8 bytes. Expected {expected_bytes}, got {content}.'


def test_tmp_directory_exists():
    """Verify that the .tmp directory exists as required for atomic writes."""
    tmp_dir = '/home/user/clean_data/.tmp'
    assert os.path.isdir(tmp_dir), f'Temporary directory {tmp_dir} does not exist.'


def test_summary_file():
    """Verify that summary.txt exists and contains the correct counts."""
    summary_file = '/home/user/summary.txt'
    assert os.path.isfile(summary_file), f'Summary file {summary_file} does not exist.'

    with open(summary_file, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f'Summary file should contain exactly 2 lines, found {len(lines)}.'
    assert lines[0] == '3', f"Expected first line to be '3' (total files), got '{lines[0]}'."
    assert lines[1] == '53', f"Expected second line to be '53' (total bytes), got '{lines[1]}'."


def test_zz_generated_additional_inputs_are_processed():
    """Exercise the compiled artifact on verifier-generated names and contents."""
    nonce = secrets.token_hex(10)
    nested = f'generated_{secrets.token_hex(6)}/deeper_{secrets.token_hex(6)}'

    generated_text = {
        f'{nested}/weather_{nonce}.win1252.txt': f'Reading {nonce}: 19°C, cost €7',
        f'{nested}/status_{nonce}.utf8.txt': f'UTF-8 {nonce}: café ✓ 東京',
        f'{nested}/power_{nonce}.utf16le.txt': f'Power {nonce}:\nBattery Ω low',
    }
    encodings = {
        'win1252': 'cp1252',
        'utf8': 'utf-8',
        'utf16le': 'utf-16le',
    }

    expected = dict(ORIGINAL_OUTPUTS)
    for relative, text in generated_text.items():
        indicator = relative.rsplit('.', 2)[1]
        raw_path = RAW / relative
        raw_path.parent.mkdir(parents=True, exist_ok=True)
        raw_path.write_bytes(text.encode(encodings[indicator]))

        output_relative = relative.rsplit('.', 2)[0] + '.txt'
        expected[output_relative] = text.encode('utf-8')

    run_cleaner()

    for relative, expected_bytes in expected.items():
        output = CLEAN / relative
        assert output.is_file(), f'Expected generated output {output} does not exist.'
        assert output.read_bytes() == expected_bytes, f'Incorrect UTF-8 conversion in {output}.'

    assert (CLEAN / '.tmp').is_dir(), 'The required clean_data/.tmp directory is missing.'
    raw_summary = SUMMARY.read_text(encoding='utf-8')
    assert raw_summary.endswith('\n'), 'summary.txt must contain two complete lines.'
    lines = raw_summary.splitlines()
    assert lines == [str(len(expected)), str(sum(map(len, expected.values())))], \
        f'Incorrect generated-run summary: {lines!r}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
