#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

import pytest

PROJECT = Path('/home/user/telemetry_parser')
DATA = Path('/home/user/data')
OUTPUT = Path('/home/user/timeline_output.json')
CORRUPTED = Path('/home/user/corrupted_lines.log')
MRE = Path('/home/user/mre.rs')


def parse_ts(value):
    # Python's parser accepts the repaired RFC3339 form.
    return datetime.fromisoformat(value.replace('Z', '+00:00'))


def run_application():
    assert PROJECT.is_dir(), f'Missing project directory {PROJECT}'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Missing Cargo.toml'
    assert (PROJECT / 'src/main.rs').is_file(), 'Missing src/main.rs'

    # Remove artifacts so only the submitted application can recreate them.
    for path in (OUTPUT, CORRUPTED):
        if path.exists():
            path.unlink()

    build = subprocess.run(
        ['cargo', 'build'], cwd=PROJECT, capture_output=True, text=True, timeout=180
    )
    assert build.returncode == 0, f'cargo build failed:\n{build.stdout}\n{build.stderr}'

    result = subprocess.run(
        ['cargo', 'run', '--quiet'], cwd=PROJECT, capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, f'application failed:\n{result.stdout}\n{result.stderr}'


def expected_from_inputs():
    valid = []
    corrupt = []
    for name in ('service_a.log', 'service_b.log', 'service_c.log'):
        with open(DATA / name, encoding='utf-8') as f:
            for raw in f:
                line = raw.rstrip('\n')
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    corrupt.append(line)
                    continue
                ts = entry['timestamp']
                if 'Z' in ts and ts.endswith('+00:00'):
                    ts = ts[:-6]
                parse_ts(ts)
                # Output object structure/content must remain unchanged.
                valid.append(entry)
    valid.sort(key=lambda entry: parse_ts(
        entry['timestamp'][:-6]
        if 'Z' in entry['timestamp'] and entry['timestamp'].endswith('+00:00')
        else entry['timestamp']
    ))
    return valid, corrupt


def test_application_is_built_run_and_outputs_are_correct():
    run_application()
    expected, expected_corrupt = expected_from_inputs()

    assert OUTPUT.is_file(), f'Expected output file {OUTPUT} does not exist.'
    with open(OUTPUT, encoding='utf-8') as f:
        data = json.load(f)
    assert isinstance(data, list), 'Timeline output must be a JSON array.'
    assert data == expected, 'Timeline must contain exactly the valid input objects in chronological order.'
    parsed = [parse_ts(e['timestamp'][:-6] if 'Z' in e['timestamp'] and e['timestamp'].endswith('+00:00') else e['timestamp']) for e in data]
    assert all(a < b for a, b in zip(parsed, parsed[1:])), 'Timeline is not strictly chronological.'

    assert CORRUPTED.is_file(), f'Expected corrupted-lines file {CORRUPTED} does not exist.'
    raw_log = CORRUPTED.read_text(encoding='utf-8')
    assert raw_log == ''.join(line + '\n' for line in expected_corrupt), 'Corrupted lines were not logged exactly, including trailing newlines.'


def test_mre_demonstrates_chrono_parse_panic():
    assert MRE.is_file(), f'MRE file {MRE} does not exist.'
    source = MRE.read_text(encoding='utf-8')
    assert '2023-10-25T14:30:00Z+00:00' in source, 'MRE does not contain the required malformed timestamp.'
    assert 'chrono' in source and 'parse_from_rfc3339' in source, 'MRE must reproduce the chrono parsing failure.'

    temp = Path('/tmp/mre_test_project')
    shutil.rmtree(temp, ignore_errors=True)
    (temp / 'src').mkdir(parents=True)
    (temp / 'Cargo.toml').write_text('''[package]\nname = "mre_test"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\nchrono = "0.4"\n''', encoding='utf-8')
    (temp / 'src/main.rs').write_text(source, encoding='utf-8')

    build = subprocess.run(['cargo', 'build', '--quiet'], cwd=temp, capture_output=True, text=True, timeout=180)
    assert build.returncode == 0, f'MRE did not compile:\n{build.stdout}\n{build.stderr}'
    result = subprocess.run([str(temp / 'target/debug/mre_test')], cwd=temp, capture_output=True, text=True, timeout=30)
    assert result.returncode != 0, 'MRE was expected to panic.'
    assert 'panicked at' in result.stderr.lower(), 'MRE failed without a Rust panic.'
    # Require the panic to arise from unwrapping chrono's parse error, rather than an explicit panic.
    assert 'parseerror' in result.stderr.lower() or 'premature' in result.stderr.lower() or 'trailing' in result.stderr.lower(), 'MRE does not demonstrate the chrono parse error.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
