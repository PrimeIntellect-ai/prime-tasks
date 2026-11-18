#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
from pathlib import Path

REPO = Path('/home/user/uptime_monitor')
TOKEN_PATH = Path('/home/user/recovered_token.txt')
OUTPUT_PATH = Path('/home/user/monitor_output.txt')
SOURCE_PATH = REPO / 'monitor.c'
BINARY_PATH = REPO / 'monitor'
EXPECTED_TOKEN = 'sre_token_99x21'
EXPECTED_OUTPUT = 'Uptime target reached.\nSLA Status: 99.999% OK\n'


def run_monitor(path, token):
    return subprocess.run(
        [str(path), token],
        cwd=str(REPO),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
        check=False,
    )


def test_recovered_token_file():
    assert TOKEN_PATH.is_file(), f'File {TOKEN_PATH} does not exist.'
    content = TOKEN_PATH.read_text().strip()
    assert content == EXPECTED_TOKEN, (
        f"Expected token '{EXPECTED_TOKEN}', but found '{content}'."
    )


def test_monitor_output_file():
    assert OUTPUT_PATH.is_file(), f'File {OUTPUT_PATH} does not exist.'
    content = OUTPUT_PATH.read_text()
    assert 'SLA Status: 99.999% OK' in content, (
        'The monitor output does not contain the expected SLA status message.'
    )
    assert content == EXPECTED_OUTPUT, 'The monitor output is not the daemon output expected from a successful run.'


def test_monitor_c_modified():
    assert SOURCE_PATH.is_file(), f'File {SOURCE_PATH} does not exist.'
    content = SOURCE_PATH.read_text()

    original_content_snippet = (
        'float uptime_seconds = 16777210.0f;\n'
        '    float target_uptime = 16777220.0f;'
    )
    is_original = original_content_snippet in content and 'uptime_seconds += 1.0f;' in content
    assert not is_original, (
        'The monitor.c file appears to be unmodified and still contains the infinite loop bug.'
    )


def test_source_compiles_and_monitor_really_runs(tmp_path):
    # Compile monitor.c independently so a fabricated output file or altered Makefile
    # cannot substitute for a real source-level fix.
    direct_binary = tmp_path / 'monitor_from_source'
    compile_result = subprocess.run(
        ['gcc', '-O0', '-g', str(SOURCE_PATH), '-o', str(direct_binary)],
        cwd=str(REPO),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert compile_result.returncode == 0, f'monitor.c did not compile:\n{compile_result.stderr}'
    assert direct_binary.read_bytes()[:4] == b'\x7fELF', 'Compiled monitor is not an ELF executable.'

    direct_run = run_monitor(direct_binary, EXPECTED_TOKEN)
    assert direct_run.returncode == 0, f'Compiled monitor failed:\n{direct_run.stderr}'
    assert direct_run.stdout == EXPECTED_OUTPUT, 'Compiled monitor produced incorrect output.'

    invalid_run = run_monitor(direct_binary, 'definitely_invalid_token')
    assert invalid_run.returncode != 0, 'Compiled monitor accepted an invalid authentication token.'
    assert 'SLA Status: 99.999% OK' not in invalid_run.stdout

    # Also require the requested make-built repository artifact to exist and work.
    if BINARY_PATH.exists() or BINARY_PATH.is_symlink():
        BINARY_PATH.unlink()
    make_result = subprocess.run(
        ['make'],
        cwd=str(REPO),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert make_result.returncode == 0, f'make failed:\n{make_result.stderr}'
    assert BINARY_PATH.is_file(), 'make did not create the monitor executable.'
    assert BINARY_PATH.read_bytes()[:4] == b'\x7fELF', 'The make-built monitor is not an ELF executable.'
    assert BINARY_PATH.stat().st_mode & stat.S_IXUSR, 'The make-built monitor is not executable.'

    made_run = run_monitor(BINARY_PATH, TOKEN_PATH.read_text().strip())
    assert made_run.returncode == 0, f'The make-built monitor failed:\n{made_run.stderr}'
    assert made_run.stdout == EXPECTED_OUTPUT, 'The make-built monitor produced incorrect output.'
    assert OUTPUT_PATH.read_text() == made_run.stdout, (
        'monitor_output.txt does not match the output of the submitted monitor.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
