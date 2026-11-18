#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from collections import Counter

EXTRACT_C = '/home/user/extract.c'
EXTRACT = '/home/user/extract'
TOP_SESSIONS = '/home/user/top_sessions.txt'
SYSTEM_LOG = '/home/user/system.log'
PATTERN = re.compile(r'SessionID: ([a-f0-9]{8})')


def run_extractor(path, data):
    result = subprocess.run(
        [path], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False
    )
    assert result.returncode == 0, (
        f'{path} exited with {result.returncode}: '
        f'{result.stderr.decode("utf-8", errors="replace")}'
    )
    try:
        output = result.stdout.decode('utf-8')
    except UnicodeDecodeError as exc:
        raise AssertionError(f'{path} did not produce UTF-8/ASCII output: {exc}')
    return output.splitlines()


def test_extract_c_exists():
    path = EXTRACT_C
    assert os.path.exists(path), f'The file {path} is missing.'
    assert os.path.isfile(path), f'The path {path} is not a file.'


def test_extract_executable_exists():
    path = EXTRACT
    assert os.path.exists(path), f'The executable {path} is missing.'
    assert os.path.isfile(path), f'The path {path} is not a file.'
    assert os.access(path, os.X_OK), f'The file {path} is not executable.'
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not a compiled ELF executable.'


def test_source_uses_posix_regex_and_compiles():
    with open(EXTRACT_C, 'r', encoding='utf-8') as f:
        source = f.read()
    assert re.search(r'#\s*include\s*[<"]regex\.h[>"]', source), \
        'extract.c must include <regex.h>.'
    assert re.search(r'\bregcomp\s*\(', source), 'extract.c must compile a POSIX regex with regcomp.'
    assert re.search(r'\bregexec\s*\(', source), 'extract.c must match with regexec.'

    result = subprocess.run(
        ['gcc', '-O2', EXTRACT_C, '-o', '/tmp/extract_from_source'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, check=False
    )
    assert result.returncode == 0, (
        'extract.c failed to compile:\n' + result.stderr.decode('utf-8', errors='replace')
    )


def test_extractors_on_fresh_utf16le_input():
    alphabet = 'abcdef0123456789'
    ids = []
    while len(ids) < 7:
        value = ''.join(secrets.choice(alphabet) for _ in range(8))
        if value not in ids:
            ids.append(value)

    lines = [
        f'INFO SessionID: {ids[0]} end',
        'DEBUG no session identifier here',
        f'WARN prefix SessionID: {ids[1]} suffix',
        'SessionID: ABCDEF12',
        'SessionID: abc1234',
        f'CRIT SessionID: {ids[2]} details',
        f'INFO SessionID: {ids[3]}',
        'SessionID: zzzzzzzz',
        f'WARN SessionID: {ids[4]} trailing text',
        f'INFO SessionID: {ids[5]} done',
        f'CRIT SessionID: {ids[6]} done',
        f'REPEAT SessionID: {ids[0]} again',
    ]
    text = '\n'.join(lines) + '\n'
    data = text.encode('utf-16le')
    expected = PATTERN.findall(text)

    assert run_extractor(EXTRACT, data) == expected
    assert run_extractor('/tmp/extract_from_source', data) == expected


def test_extractor_on_supplied_log_and_aggregation():
    with open(SYSTEM_LOG, 'rb') as f:
        raw_log = f.read()
    decoded_log = raw_log.decode('utf-16le')
    expected_ids = PATTERN.findall(decoded_log)
    actual_ids = run_extractor(EXTRACT, raw_log)
    assert actual_ids == expected_ids, 'extract output does not match the supplied UTF-16LE log.'

    counts = Counter(expected_ids)
    expected_top = [session_id for session_id, _ in sorted(
        counts.items(), key=lambda item: (-item[1], item[0])
    )[:3]]

    with open(TOP_SESSIONS, 'r', encoding='utf-8') as f:
        raw_content = f.read()
    assert raw_content == ''.join(session_id + '\n' for session_id in expected_top), \
        'top_sessions.txt must contain exactly the derived top three IDs, one per line.'


def test_top_sessions_output():
    path = TOP_SESSIONS
    assert os.path.exists(path), f'The file {path} is missing.'
    assert os.path.isfile(path), f'The path {path} is not a file.'

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read().strip().splitlines()

    content = [line.strip() for line in content if line.strip()]
    expected = ['aaaaaaaa', 'bbbbbbbb', 'cccccccc']

    assert len(content) == 3, f'Expected exactly 3 lines in {path}, but got {len(content)}.'
    assert content == expected, f'Expected {expected} in {path}, but got {content}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
