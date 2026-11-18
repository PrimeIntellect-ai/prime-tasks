#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/etl_cleaner')
MANIFEST = PROJECT / 'Cargo.toml'
RAW = Path('/home/user/raw_etl_dump.txt')
OUTPUT = Path('/home/user/processed_dataset.jsonl')

ORIGINAL_EXPECTED = [
    ('system is starting', 3, '3.00'),
    ('processing data batch 1', 4, '3.50'),
    ('data batch 2 arrived', 4, '3.67'),
    ('error in pipeline', 3, '3.67'),
    ('retrying batch 2', 3, '3.33'),
    ('batch 3 processing', 3, '3.00'),
]

AVG_PATTERN = re.compile(r'"rolling_avg"\s*:\s*(-?\d+\.\d{2})(?=\s*[,}])')


def verify_output(expected):
    assert OUTPUT.is_file(), f'Output file not found at {OUTPUT}.'
    with OUTPUT.open('r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected), (
        f'Expected {len(expected)} lines in {OUTPUT}, but got {len(lines)}.'
    )

    for i, (line, (expected_text, expected_words, expected_avg)) in enumerate(zip(lines, expected), 1):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f'Line {i} is not valid JSON: {line}')

        assert 'text' in data, f"Line {i} missing 'text' key."
        assert 'words' in data, f"Line {i} missing 'words' key."
        assert 'rolling_avg' in data, f"Line {i} missing 'rolling_avg' key."
        assert data['text'] == expected_text, (
            f"Line {i} text mismatch. Expected '{expected_text}', got '{data['text']}'"
        )
        assert data['words'] == expected_words, (
            f"Line {i} words mismatch. Expected {expected_words}, got {data['words']}"
        )

        # Preserve the original numeric tolerance assertion.
        actual_avg = float(data['rolling_avg'])
        assert abs(actual_avg - float(expected_avg)) < 0.015, (
            f'Line {i} rolling_avg mismatch. Expected {expected_avg}, got {actual_avg}'
        )

        # JSON numbers preserve their required two decimal places lexically.
        matches = AVG_PATTERN.findall(line)
        assert len(matches) == 1, (
            f'Line {i} rolling_avg must be a JSON number written with exactly two decimal places: {line}'
        )
        assert matches[0] == expected_avg, (
            f'Line {i} rolling_avg formatting/value mismatch. Expected {expected_avg}, got {matches[0]}'
        )


def run_program():
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(MANIFEST)],
        cwd=str(PROJECT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f'Rust program failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def make_random_fixture():
    rng = secrets.SystemRandom()
    nonce = secrets.token_hex(8)
    counts = [1, 8, 2, rng.randint(3, 7), rng.randint(1, 8), rng.randint(2, 6), 4]
    normalized = []
    raw_lines = ['', '       ']

    for record_index, count in enumerate(counts):
        tokens = [f'w{record_index}_{token_index}_{nonce}' for token_index in range(count)]
        text = ' '.join(tokens)
        normalized.append(text)
        separator = ' ' * rng.randint(2, 5)
        raw_lines.append((' ' * rng.randint(1, 4)) + separator.join(tokens).upper() + (' ' * rng.randint(1, 4)))

    # Non-adjacent duplicates with different case and spacing must be skipped.
    for index in (2, 0, 5, 2, 6):
        raw_lines.append('   ' + ('   '.join(normalized[index].split())).upper() + '   ')
    raw_lines.append('   ')

    expected = []
    window = []
    for text, count in zip(normalized, counts):
        window.append(count)
        if len(window) > 3:
            window.pop(0)
        expected.append((text, count, f'{sum(window) / len(window):.2f}'))

    return '\n'.join(raw_lines) + '\n', expected


def test_cargo_project_exists():
    assert MANIFEST.is_file(), f'Cargo project not found. Expected {MANIFEST} to exist.'


def test_processed_dataset_and_executable_behavior():
    # Retain the original assertion against the output the agent generated.
    verify_output(ORIGINAL_EXPECTED)

    original_raw = RAW.read_bytes()
    original_output = OUTPUT.read_bytes()
    try:
        build = subprocess.run(
            ['cargo', 'build', '--manifest-path', str(MANIFEST)],
            cwd=str(PROJECT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=240,
        )
        assert build.returncode == 0, (
            f'Cargo project did not build.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}'
        )

        # Re-run on the supplied fixture so the checked output must come from the Rust program.
        OUTPUT.unlink()
        run_program()
        verify_output(ORIGINAL_EXPECTED)

        # Exercise normalization, deduplication, token counts, and rolling windows on
        # unpredictable inputs whose answers are derived by the verifier.
        for _ in range(2):
            fixture, expected = make_random_fixture()
            RAW.write_text(fixture, encoding='utf-8')
            if OUTPUT.exists():
                OUTPUT.unlink()
            run_program()
            verify_output(expected)

        # The requested output mode is append rather than truncate.
        run_program()
        verify_output(expected + expected)
    finally:
        RAW.write_bytes(original_raw)
        OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
