#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import os
import re
import sqlite3
import subprocess
from pathlib import Path

import pytest

ROOT = Path('/home/user/log_pipeline')
PYTHON = ROOT / 'venv/bin/python'
SCRIPT = ROOT / 'process_logs.py'
REQUIREMENTS = ROOT / 'requirements.txt'
DB_PATH = ROOT / 'data/metadata.db'
LOG_PATH = ROOT / 'data/raw_logs.jsonl'
OUT_PATH = ROOT / 'output/summary.json'


def get_expected_summary():
    """Compute the expected summary using the required relational join and bad-JSON handling."""
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute('''
            SELECT servers.ip, regions.name
            FROM servers
            JOIN regions ON servers.region_id = regions.id
        ''').fetchall()
    finally:
        conn.close()
    mapping = dict(rows)

    counts = {}
    with open(LOG_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if record.get('level') == 'ERROR':
                region = mapping.get(record.get('ip'), 'unknown')
                counts[region] = counts.get(region, 0) + 1
    return counts


def run_pipeline():
    if OUT_PATH.exists():
        OUT_PATH.unlink()
    result = subprocess.run(
        [str(PYTHON), str(SCRIPT)],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        'The pipeline script failed when executed with its virtual environment.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUT_PATH.is_file(), 'The executed pipeline did not create output/summary.json.'
    try:
        with open(OUT_PATH, 'r', encoding='utf-8') as f:
            value = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'Output file {OUT_PATH} does not contain valid JSON: {exc}')
    assert isinstance(value, dict), 'summary.json must contain a JSON object.'
    assert all(isinstance(k, str) for k in value), 'All summary keys must be strings.'
    assert all(type(v) is int for v in value.values()), 'All summary counts must be integers.'
    return value


@pytest.fixture(scope='session', autouse=True)
def restore_pipeline_files():
    paths = [DB_PATH, LOG_PATH, OUT_PATH]
    saved = {path: path.read_bytes() if path.exists() else None for path in paths}
    yield
    for path, contents in saved.items():
        if contents is None:
            if path.exists():
                path.unlink()
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)


def test_01_venv_setup_and_dependencies():
    """The requested path must be a real venv with all fixed requirements installed."""
    assert PYTHON.is_file(), (
        f'Virtual environment python executable not found at {PYTHON}. '
        'Ensure the virtual environment was created in the correct location.'
    )
    assert os.access(PYTHON, os.X_OK), f'{PYTHON} is not executable.'
    assert REQUIREMENTS.is_file(), 'requirements.txt is missing.'

    prefix_check = subprocess.run(
        [str(PYTHON), '-c',
         "import os,sys; expected=os.path.realpath('/home/user/log_pipeline/venv'); "
         "assert os.path.realpath(sys.prefix)==expected, (sys.prefix, expected); "
         "assert sys.prefix != sys.base_prefix"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15,
    )
    assert prefix_check.returncode == 0, (
        f'{PYTHON} is not the Python interpreter of the required virtual environment:\n'
        f'{prefix_check.stderr}'
    )

    requirement_check = subprocess.run(
        [str(PYTHON), '-c', r'''
from importlib.metadata import version
from pip._vendor.packaging.requirements import Requirement
from pip._vendor.packaging.utils import canonicalize_name

path = '/home/user/log_pipeline/requirements.txt'
requirements = []
for raw in open(path, encoding='utf-8'):
    line = raw.strip()
    if not line or line.startswith('#'):
        continue
    req = Requirement(line)
    if req.marker is None or req.marker.evaluate():
        requirements.append(req)

names = {canonicalize_name(req.name) for req in requirements}
assert 'requests' in names, 'requirements.txt must retain requests'
assert 'urllib3' in names, 'requirements.txt must retain urllib3'
for req in requirements:
    installed = version(req.name)
    assert not req.specifier or req.specifier.contains(installed, prereleases=True), \
        f'{req} is required but installed version is {installed}'
'''],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15,
    )
    assert requirement_check.returncode == 0, (
        'requirements.txt is not satisfied by the required virtual environment:\n'
        f'{requirement_check.stdout}{requirement_check.stderr}'
    )

    pip_check = subprocess.run(
        [str(PYTHON), '-m', 'pip', 'check'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30,
    )
    assert pip_check.returncode == 0, (
        'Installed dependencies still contain a version conflict:\n'
        f'{pip_check.stdout}{pip_check.stderr}'
    )


def test_02_execute_pipeline_on_original_input():
    """Execute the submitted script and retain the original exact-summary assertion."""
    expected_summary = get_expected_summary()
    actual_summary = run_pipeline()
    assert actual_summary == expected_summary, (
        f'The data in {OUT_PATH} is incorrect.\n'
        f'Expected: {expected_summary}\nActual: {actual_summary}\n'
        'Check that the SQL query joins on region_id and invalid JSON lines are skipped.'
    )


def test_03_sql_fix_and_corrupted_input_handling():
    """Exercise the script on fresh data containing cross-join traps and invalid UTF-8."""
    source = SCRIPT.read_text(encoding='utf-8')
    lowered = source.lower()
    assert not re.search(r'from\s+servers\s*,\s*regions', lowered), (
        'process_logs.py still contains the Cartesian-product query.'
    )
    assert re.search(r'\bjoin\b', lowered) and re.search(r'\bon\b', lowered) and 'region_id' in lowered, (
        'process_logs.py must contain a SQL join condition using region_id.'
    )

    if DB_PATH.exists():
        DB_PATH.unlink()
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE regions (id INTEGER PRIMARY KEY, name TEXT)')
        conn.execute('CREATE TABLE servers (ip TEXT PRIMARY KEY, region_id INTEGER)')
        conn.executemany(
            'INSERT INTO regions (id, name) VALUES (?, ?)',
            [(11, 'test-north'), (22, 'test-south'), (99, 'cross-join-decoy')],
        )
        conn.executemany(
            'INSERT INTO servers (ip, region_id) VALUES (?, ?)',
            [('alpha', 11), ('beta', 22)],
        )
        conn.commit()
    finally:
        conn.close()

    LOG_PATH.write_bytes(
        b'{"ip":"alpha","level":"ERROR"}\n'
        b'{"ip":"alpha","level":"ERROR"}\n'
        b'{"ip":"alpha","level":"ERROR"\n'
        b'{"ip":"alpha","level":"ERROR","message":\xff}\n'
        b'{bad_json_here: true}\n'
        b'{"ip":"beta","level":"INFO"}\n'
        b'{"ip":"beta","level":"ERROR"}\n'
        b'{"ip":"not-in-db","level":"ERROR"}\n'
    )

    actual = run_pipeline()
    expected = {'test-north': 2, 'test-south': 1, 'unknown': 1}
    assert actual == expected, (
        'The pipeline did not correctly join servers to regions and continue past '
        f'truncated/invalid-UTF-8 JSON lines. Expected {expected}, got {actual}.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
