#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 <<'PY'
import json
import os
import pathlib
import sqlite3
import subprocess
import uuid

repo = pathlib.Path('/home/user/reconciler')
source = repo / 'main.go'
token_path = pathlib.Path('/home/user/token.txt')
state_path = pathlib.Path('/home/user/converged_state.json')
db_path = pathlib.Path('/home/user/data/config.db')
expected_token = 'super_secret_devops_token_99'

assert source.is_file(), f'Missing Go source: {source}'
assert token_path.is_file(), f'Missing token file: {token_path}'
token = token_path.read_text().strip()
assert token == expected_token, f'Token in {token_path} is incorrect.'
assert expected_token not in source.read_text(), 'The recovered token was hardcoded back into main.go.'

binary = '/tmp/reconciler-under-test'
build = subprocess.run(
    ['go', 'build', '-race', '-o', binary, '.'],
    cwd=repo,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    timeout=120,
)
assert build.returncode == 0, f'Go program did not compile:\n{build.stdout}'

def install_rows(rows):
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()
    con = sqlite3.connect(db_path)
    try:
        con.execute('CREATE TABLE config (id INTEGER PRIMARY KEY, key TEXT, val TEXT, active INTEGER)')
        con.executemany('INSERT INTO config (key, val, active) VALUES (?, ?, ?)', rows)
        con.commit()
    finally:
        con.close()

def run_with(secret):
    env = os.environ.copy()
    env['SECRET_TOKEN'] = secret
    return subprocess.run(
        [binary],
        cwd=repo,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )

# Preserve and exercise the authentication assertion independently of existing files.
install_rows([('auth_probe', 'yes', 1)])
state_path.unlink(missing_ok=True)
bad = run_with('definitely-wrong-token')
assert bad.returncode != 0, 'Program accepted an incorrect SECRET_TOKEN.'
assert not state_path.exists(), 'Program generated state despite failed authentication.'

# Exercise database filtering, concurrent updates, convergence, and file generation
# using verifier-generated values. The race-enabled binary also reports unsafe map access.
for round_no in range(3):
    marker = uuid.uuid4().hex
    active = [(f'active_{round_no}_{i}_{marker}', f'value_{i}_{marker}', 1) for i in range(400)]
    inactive = [(f'inactive_{round_no}_{i}_{marker}', f'forbidden_{i}_{marker}', 0) for i in range(80)]
    rows = active + inactive
    install_rows(rows)
    expected = {k: v for k, v, enabled in rows if enabled == 1}
    state_path.unlink(missing_ok=True)

    result = run_with(expected_token)
    assert result.returncode == 0, f'Program failed to run successfully:\n{result.stdout}'
    assert 'DATA RACE' not in result.stdout, f'Race detector reported unsafe concurrency:\n{result.stdout}'
    assert state_path.is_file(), 'Program did not generate converged_state.json.'
    try:
        actual = json.loads(state_path.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError('converged_state.json is not valid JSON.') from exc
    assert actual == expected, 'Generated state did not exactly match the active database rows.'

# Retain the original final-state assertion on the canonical database contents.
canonical_rows = [
    ('worker_threads', '4', 1),
    ('debug_mode', 'true', 1),
    ('old_setting', 'obsolete', 0),
]
install_rows(canonical_rows)
state_path.unlink(missing_ok=True)
final_run = run_with(expected_token)
assert final_run.returncode == 0, f'Program failed on canonical input:\n{final_run.stdout}'
assert state_path.is_file(), f'File {state_path} is missing.'
try:
    final_state = json.loads(state_path.read_text())
except json.JSONDecodeError as exc:
    raise AssertionError(f'File {state_path} does not contain valid JSON.') from exc
assert final_state == {'debug_mode': 'true', 'worker_threads': '4'}, 'Canonical converged state is incorrect.'
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
