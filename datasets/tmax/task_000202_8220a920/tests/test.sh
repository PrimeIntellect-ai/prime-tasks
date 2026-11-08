#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

EXTRACTOR_DIR = Path('/app/graph-backup-extractor-v2.1.0')
EXTRACTOR = EXTRACTOR_DIR / 'bin/extractor'
SANITIZER = Path('/app/sanitizer')
SANITIZER_SOURCE = Path('/app/sanitizer.go')
RESULTS_LOG = Path('/app/sanitizer_results.log')


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(map(str, command))}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def parse_classifications(result, expected_names):
    assert result.returncode == 0, (
        f"Sanitizer exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    classifications = {}
    pattern = re.compile(r'^(ACCEPTED|REJECTED): (.+)$')
    for raw_line in result.stdout.splitlines():
        match = pattern.fullmatch(raw_line.strip())
        if not match:
            continue
        verdict, name = match.groups()
        assert name in expected_names, f"Unexpected filename in sanitizer output: {name}"
        assert name not in classifications, f"Duplicate classification for {name}"
        classifications[name] = verdict
    assert set(classifications) == set(expected_names), (
        f"Expected classifications for {sorted(expected_names)}, got {sorted(classifications)}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return classifications


def run_sanitizer(binary, directory, expected):
    result = subprocess.run([str(binary), str(directory)], capture_output=True, text=True)
    actual = parse_classifications(result, set(expected))
    assert actual == expected, f"Incorrect classifications: expected {expected}, got {actual}"


def test_extractor_built_and_repaired():
    assert (EXTRACTOR_DIR / 'Makefile').is_file(), 'Extractor Makefile is missing.'
    assert (EXTRACTOR_DIR / 'config.go').is_file(), 'Extractor config.go is missing.'
    assert (EXTRACTOR_DIR / 'main.go').is_file(), 'Extractor main.go is missing.'

    # Compile the submitted Go sources directly before invoking make, ensuring the
    # config.go repair itself maps NEO4J_URI rather than relying on a Makefile side effect.
    uri = 'neo4j://verification-' + secrets.token_hex(12) + ':7687'
    env = os.environ.copy()
    env['NEO4J_URI'] = uri
    direct_binary = Path(tempfile.mkdtemp(prefix='extractor-source-')) / 'extractor'
    run_checked(
        ['go', 'build', '-o', str(direct_binary), 'main.go', 'config.go'],
        cwd=EXTRACTOR_DIR,
        env=env,
    )
    direct_result = run_checked([str(direct_binary)], cwd=EXTRACTOR_DIR, env=env)
    assert uri in direct_result.stdout, 'Extractor sources do not map NEO4J_URI into the loaded configuration.'

    # The requested build must be produced by a successful make build, not merely
    # left behind as a pre-existing executable.
    if EXTRACTOR.exists() or EXTRACTOR.is_symlink():
        EXTRACTOR.unlink()
    run_checked(['make', 'build'], cwd=EXTRACTOR_DIR, env=env)

    assert EXTRACTOR.is_file(), f'Extractor binary not found at {EXTRACTOR}. Did you run make build?'
    assert os.access(EXTRACTOR, os.X_OK), f'Extractor binary at {EXTRACTOR} is not executable.'
    built_result = run_checked([str(EXTRACTOR)], cwd=EXTRACTOR_DIR, env=env)
    assert uri in built_result.stdout, 'The make-built extractor does not use NEO4J_URI.'


def test_sanitizer_built():
    assert SANITIZER.is_file(), f'Sanitizer binary not found at {SANITIZER}.'
    assert os.access(SANITIZER, os.X_OK), f'Sanitizer binary at {SANITIZER} is not executable.'
    assert SANITIZER_SOURCE.is_file(), f'Go source not found at {SANITIZER_SOURCE}.'


def test_sanitizer_clean_corpus():
    clean_dir = Path('/app/corpora/clean')
    assert clean_dir.is_dir(), f'Clean corpus directory {clean_dir} missing.'
    files = [p.name for p in clean_dir.iterdir() if p.name.endswith('.json')]
    assert files, 'No JSON files found in clean corpus.'

    result = subprocess.run([str(SANITIZER), str(clean_dir)], capture_output=True, text=True)
    output = result.stdout + '\n' + result.stderr
    rejected = []
    missing = []
    for name in files:
        if f'REJECTED: {name}' in output:
            rejected.append(name)
        elif f'ACCEPTED: {name}' not in output:
            missing.append(name)
    errors = []
    if rejected:
        errors.append(f'{len(rejected)} of {len(files)} clean files were incorrectly REJECTED: {", ".join(rejected[:5])}')
    if missing:
        errors.append(f'{len(missing)} of {len(files)} clean files were not ACCEPTED: {", ".join(missing[:5])}')
    assert result.returncode == 0, f'Sanitizer failed on clean corpus: {result.stderr}'
    assert not errors, 'Clean corpus validation failed:\n' + '\n'.join(errors)


def test_sanitizer_evil_corpus():
    evil_dir = Path('/app/corpora/evil')
    assert evil_dir.is_dir(), f'Evil corpus directory {evil_dir} missing.'
    files = [p.name for p in evil_dir.iterdir() if p.name.endswith('.json')]
    assert files, 'No JSON files found in evil corpus.'

    result = subprocess.run([str(SANITIZER), str(evil_dir)], capture_output=True, text=True)
    output = result.stdout + '\n' + result.stderr
    accepted = []
    missing = []
    for name in files:
        if f'ACCEPTED: {name}' in output:
            accepted.append(name)
        elif f'REJECTED: {name}' not in output:
            missing.append(name)
    errors = []
    if accepted:
        errors.append(f'{len(accepted)} of {len(files)} evil files bypassed and were ACCEPTED: {", ".join(accepted[:5])}')
    if missing:
        errors.append(f'{len(missing)} of {len(files)} evil files were not REJECTED: {", ".join(missing[:5])}')
    assert result.returncode == 0, f'Sanitizer failed on evil corpus: {result.stderr}'
    assert not errors, 'Evil corpus validation failed:\n' + '\n'.join(errors)


def test_sanitizer_on_unseen_documents():
    token = secrets.token_hex(10)
    root = Path(tempfile.mkdtemp(prefix='backup-verification-'))
    clean_dir = root / ('ordinary-' + secrets.token_hex(6))
    evil_dir = root / ('ordinary-' + secrets.token_hex(6))
    clean_dir.mkdir()
    evil_dir.mkdir()

    clean_documents = [
        {'safe': True, 'customer': token, 'relationships': [{'kind': 'depends_on', 'active': True}]},
        {'profile': {'name': 'Customer ' + token, 'contact': {'email': token + '@example.test'}}, 'count': 7},
        {'records': [{'id': secrets.token_hex(5), 'value': 'normal'}, {'id': secrets.token_hex(5), 'value': 'archived'}]},
    ]
    evil_documents = [
        {'filter': {'$where': 'function() { return this.customer == "' + token + '"; }'}},
        {'login': {'username': token, 'password': {'$ne': None}}},
        {'customer': token, 'profile': {'government_id': '482-73-1609'}},
        {'outer': {'inner': {'candidate': {'$ne': token}}}},
    ]

    clean_expected = {}
    evil_expected = {}
    for document in clean_documents:
        name = secrets.token_hex(9) + '.json'
        (clean_dir / name).write_text(json.dumps(document), encoding='utf-8')
        clean_expected[name] = 'ACCEPTED'
    for document in evil_documents:
        name = secrets.token_hex(9) + '.json'
        (evil_dir / name).write_text(json.dumps(document), encoding='utf-8')
        evil_expected[name] = 'REJECTED'

    # Exercise both the requested artifact and a fresh compilation of sanitizer.go.
    source_binary = root / 'sanitizer-from-source'
    run_checked(['go', 'build', '-o', str(source_binary), str(SANITIZER_SOURCE)], cwd='/app')
    for binary in (SANITIZER, source_binary):
        run_sanitizer(binary, clean_dir, clean_expected)
        run_sanitizer(binary, evil_dir, evil_expected)


def test_sanitizer_results_log():
    assert RESULTS_LOG.is_file(), f'Required results log not found at {RESULTS_LOG}.'
    text = RESULTS_LOG.read_text(encoding='utf-8', errors='replace')
    assert text.strip(), 'sanitizer_results.log is empty.'

    clean_files = [p.name for p in Path('/app/corpora/clean').iterdir() if p.name.endswith('.json')]
    evil_files = [p.name for p in Path('/app/corpora/evil').iterdir() if p.name.endswith('.json')]
    missing = [f'ACCEPTED: {name}' for name in clean_files if f'ACCEPTED: {name}' not in text]
    missing += [f'REJECTED: {name}' for name in evil_files if f'REJECTED: {name}' not in text]
    assert not missing, f'sanitizer_results.log is missing required test results: {missing[:10]}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
