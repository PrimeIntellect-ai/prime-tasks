#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import sys
import tempfile
from pathlib import Path

TOOL_PATH = Path('/home/user/build_tool.py')
MANIFEST_PATH = Path('/home/user/system_manifest.conf')
OUTPUT_PATH = Path('/home/user/build_output.txt')


def run_tool(manifest, output):
    result = subprocess.run(
        [sys.executable, str(TOOL_PATH), '--manifest', str(manifest), '--output', str(output)],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'build_tool.py failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert output.is_file(), f'Expected output file was not created: {output}'


def test_01_build_output_exists_and_correct():
    assert TOOL_PATH.is_file(), f'Verification failed: {TOOL_PATH} is not a regular file.'
    assert MANIFEST_PATH.is_file(), f'Verification failed: {MANIFEST_PATH} not found.'

    if OUTPUT_PATH.is_symlink() or OUTPUT_PATH.is_file():
        OUTPUT_PATH.unlink()

    run_tool(MANIFEST_PATH, OUTPUT_PATH)

    with open(OUTPUT_PATH, 'r') as f:
        content = f.read().strip()

    expected_content = (
        'core_kernel:1.0.4 [none]\n'
        'lib_network:2.1.0 [core_kernel]\n'
        'audio_driver:1.1.2 [core_kernel]'
    )

    assert content == expected_content, 'Verification failed: Content of build_output.txt does not match expected output. Ensure malformed lines are skipped entirely.'


def test_02_executes_parser_on_unseen_manifest_and_skips_all_malformed_lines():
    token = secrets.token_hex(10)
    valid_entries = [
        (f'component_{token}', f'1.{secrets.randbelow(1000)}.0', 'none'),
        (f'library_{secrets.token_hex(8)}', f'2.{secrets.randbelow(1000)}.7', f'component_{token}'),
        (f'final_{secrets.token_hex(8)}', '9.8.7', f'library_{token}'),
    ]

    lines = [
        '# dynamically generated manifest',
        '',
        f'broken_{secrets.token_hex(8)}',
        f'{valid_entries[0][0]}, {valid_entries[0][1]}, {valid_entries[0][2]}',
        f'two_{secrets.token_hex(8)}, fields_only',
        f'{valid_entries[1][0]} , {valid_entries[1][1]} , {valid_entries[1][2]}',
        f'four_{secrets.token_hex(8)}, 1.0, none, unexpected',
        f'{valid_entries[2][0]}, {valid_entries[2][1]}, {valid_entries[2][2]}',
    ]
    expected = ''.join(f'{name}:{version} [{deps}]\n' for name, version, deps in valid_entries)

    with tempfile.TemporaryDirectory() as tmp:
        manifest = Path(tmp) / 'manifest.conf'
        output = Path(tmp) / 'result.txt'
        manifest.write_text('\n'.join(lines), encoding='utf-8')
        run_tool(manifest, output)
        assert output.read_text(encoding='utf-8') == expected


def test_03_empty_manifest_terminates_cleanly():
    with tempfile.TemporaryDirectory() as tmp:
        manifest = Path(tmp) / 'empty.conf'
        output = Path(tmp) / 'empty-output.txt'
        manifest.write_text('', encoding='utf-8')
        run_tool(manifest, output)
        assert output.read_text(encoding='utf-8') == ''
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
