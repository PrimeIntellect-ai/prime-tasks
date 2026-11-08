#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

REPO = Path('/home/user/log_parser')
PARSER = REPO / 'parser'
PARSER_SOURCE = REPO / 'parser.c'
MAKEFILE = REPO / 'Makefile'
RECOVERED = Path('/home/user/recovered_data.json')
VALIDATOR = Path('/home/user/validator')
VALIDATOR_SOURCE = Path('/home/user/validator.c')
WAL = Path('/app/customer.wal')
EXPECTED = {
    'status': 'recovered',
    'records': [
        {'id': 1, 'fault': 'OOM'},
        {'id': 2, 'fault': 'TIMEOUT'},
    ],
}
EXPECTED_STDOUT = b'{"status": "recovered", "records": [{"id": 1, "fault": "OOM"}, {"id": 2, "fault": "TIMEOUT"}]}\n'


def run(cmd, **kwargs):
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('timeout', 15)
    return subprocess.run(cmd, **kwargs)


def test_recovered_data():
    assert RECOVERED.is_file(), f'Recovered data file not found at {RECOVERED}.'
    try:
        with RECOVERED.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'File {RECOVERED} does not contain valid JSON.')
    assert data == EXPECTED, f'Recovered data does not match expected output. Got: {data}'


def test_makefile_repaired_and_parser_built_from_fixed_source(tmp_path):
    assert REPO.is_dir() and (REPO / '.git').exists(), 'log_parser git repository is missing.'
    assert MAKEFILE.is_file(), 'Makefile is missing.'
    assert PARSER_SOURCE.is_file(), 'parser.c is missing.'

    make_text = MAKEFILE.read_text(errors='replace').lower()
    assert 'audio_legacy' not in make_text, 'Makefile still references the incompatible legacy audio library.'
    assert 'audio_v2' in make_text, 'Makefile does not use the compatible audio_v2 dependency.'

    if PARSER.exists():
        PARSER.unlink()
    built = run(['make', '-B', 'parser'], cwd=REPO)
    assert built.returncode == 0, f'make failed:\n{built.stdout.decode(errors="replace")}\n{built.stderr.decode(errors="replace")}'
    assert PARSER.is_file() and os.access(PARSER, os.X_OK), 'make did not produce an executable parser.'

    # The original regression crashes this no-argument execution.
    no_args = run([str(PARSER)], cwd=REPO)
    assert no_args.returncode == 0, f'Built parser still fails its boundary-condition path (exit {no_args.returncode}).'

    tests = run(['make', 'test'], cwd=REPO)
    assert tests.returncode == 0, f'make test failed:\n{tests.stdout.decode(errors="replace")}\n{tests.stderr.decode(errors="replace")}'

    # Independently compile parser.c so a Makefile cannot conceal an unfixed source file.
    source_parser = tmp_path / 'parser-from-source'
    compiled = run(['gcc', '-o', str(source_parser), str(PARSER_SOURCE), '-laudio_v2'])
    assert compiled.returncode == 0, f'parser.c does not compile:\n{compiled.stderr.decode(errors="replace")}'
    source_no_args = run([str(source_parser)])
    assert source_no_args.returncode == 0, 'parser.c still contains the crashing off-by-one behavior.'


def test_bisect_identified_first_bad_commit(tmp_path):
    tag = run(['git', 'rev-parse', 'v1.0'], cwd=REPO)
    assert tag.returncode == 0, 'The known-good v1.0 tag is unavailable.'

    changed = run(['git', 'rev-list', '--reverse', 'v1.0..HEAD', '--', 'parser.c'], cwd=REPO)
    commits = changed.stdout.decode().split()
    assert commits, 'Could not identify the parser regression commit in repository history.'
    first_bad = commits[0]

    def historical_make_test(revision, directory):
        directory.mkdir()
        archive = subprocess.Popen(['git', 'archive', revision], cwd=REPO, stdout=subprocess.PIPE)
        extract = subprocess.run(['tar', '-x', '-C', str(directory)], stdin=archive.stdout, capture_output=True)
        archive.stdout.close()
        archive_rc = archive.wait()
        assert archive_rc == 0 and extract.returncode == 0, f'Could not inspect historical revision {revision}.'
        return run(['make', 'test'], cwd=directory)

    good_result = historical_make_test('v1.0', tmp_path / 'good')
    bad_result = historical_make_test(first_bad, tmp_path / 'bad')
    assert good_result.returncode == 0, 'The designated good revision does not pass make test.'
    assert bad_result.returncode != 0, 'The identified regression commit does not reproduce the parser failure.'

    # git bisect checks out candidate commits; that action remains in the reflog after bisect reset.
    reflog = run(['git', 'reflog', '--all', '--format=%gs'], cwd=REPO)
    evidence = reflog.stdout.decode(errors='replace')
    bisect_log = REPO / '.git' / 'BISECT_LOG'
    active_log = bisect_log.read_text(errors='replace') if bisect_log.exists() else ''
    assert first_bad[:7] in evidence or first_bad in active_log, \
        f'No git-bisect checkout/result evidence was found for first bad commit {first_bad}.'


def test_parser_performs_recovery_and_stdout_was_saved(tmp_path):
    assert WAL.is_file(), 'Customer WAL is missing.'
    assert PARSER.is_file() and os.access(PARSER, os.X_OK), 'Compiled parser is missing or not executable.'

    command = [str(PARSER), '--key', 'ECHO', 'DELTA', 'SEVEN', str(WAL)]
    result = run(command, cwd=REPO)
    assert result.returncode == 0, f'Parser recovery command failed with exit code {result.returncode}.'
    assert result.stdout == EXPECTED_STDOUT, f'Parser produced unexpected recovery output: {result.stdout!r}'
    assert RECOVERED.read_bytes() == result.stdout, 'recovered_data.json is not the exact stdout of the parser recovery command.'

    wrong_key = run([str(PARSER), '--key', 'WRONG', 'CODE', str(WAL)], cwd=REPO)
    assert wrong_key.stdout != EXPECTED_STDOUT, 'Parser emits recovered records without the transcribed distress code.'


def check_validator(binary, cases):
    for path, expected in cases:
        result = run([str(binary), str(path)])
        assert result.returncode == expected, \
            f'{binary} returned {result.returncode} for {path.name}; expected {expected}.'
    assert run([str(binary)]).returncode == 1, f'{binary} must reject a missing file argument with exit code 1.'
    assert run([str(binary), str(cases[0][0]), str(cases[0][0])]).returncode == 1, \
        f'{binary} must reject extra arguments with exit code 1.'


def test_validator_adversarial_corpus():
    assert VALIDATOR.is_file(), f'Validator binary not found at {VALIDATOR}.'
    assert os.access(VALIDATOR, os.X_OK), f'Validator binary at {VALIDATOR} is not executable.'

    evil_dir = '/app/corpus/evil'
    clean_dir = '/app/corpus/clean'
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)] if os.path.isdir(evil_dir) else []
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)] if os.path.isdir(clean_dir) else []

    evil_bypassed = []
    for f in evil_files:
        if run([str(VALIDATOR), f]).returncode == 0:
            evil_bypassed.append(os.path.basename(f))

    clean_modified = []
    for f in clean_files:
        if run([str(VALIDATOR), f]).returncode != 0:
            clean_modified.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f'{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {", ".join(evil_bypassed)}')
    if clean_modified:
        errors.append(f'{len(clean_modified)} of {len(clean_files)} clean modified: {", ".join(clean_modified)}')
    if errors:
        pytest.fail(' | '.join(errors))


def test_validator_binary_format_on_generated_secret_paths(tmp_path):
    assert VALIDATOR_SOURCE.is_file(), 'validator.c is missing.'
    assert VALIDATOR.read_bytes()[:4] == b'\x7fELF', 'validator is not a compiled native executable.'

    rebuilt = tmp_path / ('rebuilt-' + secrets.token_hex(8))
    compile_result = run(['gcc', '-std=c11', '-Wall', '-Wextra', '-o', str(rebuilt), str(VALIDATOR_SOURCE)])
    assert compile_result.returncode == 0, f'validator.c does not compile:\n{compile_result.stderr.decode(errors="replace")}'

    corpus = tmp_path / ('generated-' + secrets.token_hex(10))
    corpus.mkdir()
    cases = []

    lengths = [0, 1, 2, 3, 4, 7, 31, 127, 254, 255]
    lengths += [secrets.randbelow(256) for _ in range(20)]
    for index, n in enumerate(lengths):
        payload = secrets.token_bytes(n)
        valid = corpus / f'{secrets.token_hex(8)}-{index}.dat'
        valid.write_bytes(bytes([0xAA, n]) + payload)
        cases.append((valid, 0))

        bad_magic = corpus / f'{secrets.token_hex(8)}-{index}.blob'
        magic = secrets.choice([x for x in range(256) if x != 0xAA])
        bad_magic.write_bytes(bytes([magic, n]) + payload)
        cases.append((bad_magic, 1))

        trailing = corpus / f'{secrets.token_hex(8)}-{index}.raw'
        trailing.write_bytes(bytes([0xAA, n]) + payload + secrets.token_bytes(1 + secrets.randbelow(5)))
        cases.append((trailing, 1))

        if n > 0:
            truncated = corpus / f'{secrets.token_hex(8)}-{index}.evt'
            truncated.write_bytes(bytes([0xAA, n]) + payload[:-1])
            cases.append((truncated, 1))

    empty = corpus / secrets.token_hex(12)
    empty.write_bytes(b'')
    one_byte = corpus / secrets.token_hex(12)
    one_byte.write_bytes(b'\xAA')
    nonexistent = corpus / ('missing-' + secrets.token_hex(12))
    cases.extend([(empty, 1), (one_byte, 1), (nonexistent, 1)])

    check_validator(VALIDATOR, cases)
    check_validator(rebuilt, cases)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
