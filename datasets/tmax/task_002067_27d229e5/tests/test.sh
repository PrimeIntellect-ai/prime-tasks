#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile

import cv2
import numpy as np

BINARY_PATH = '/home/user/config_filter'
SOURCE_PATH = '/home/user/config_filter.c'


def run_filter(binary, payload):
    result = subprocess.run([binary], input=payload, capture_output=True, timeout=10)
    assert result.returncode == 0, f'{binary} exited with status {result.returncode}: {result.stderr!r}'
    return result.stdout


def test_config_filter_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f'C binary not found at {BINARY_PATH}'
    assert os.access(BINARY_PATH, os.X_OK), f'C binary at {BINARY_PATH} is not executable'
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'config_filter is not a compiled ELF executable'


def test_config_filter_source_is_c_and_uses_regex():
    assert os.path.isfile(SOURCE_PATH), f'C source not found at {SOURCE_PATH}'
    with open(SOURCE_PATH, 'rb') as f:
        source = f.read()

    assert re.search(rb'#\s*include\s*[<"]regex\.h[>"]', source), 'C source must include regex.h'
    assert re.search(rb'\bregcomp\s*\(', source), 'C source must compile a regular expression with regcomp'
    assert re.search(rb'\bregexec\s*\(', source), 'C source must detect matches with regexec'

    rebuilt = '/tmp/config_filter_rebuilt'
    result = subprocess.run(
        ['gcc', '-std=c11', SOURCE_PATH, '-o', rebuilt],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f'config_filter.c does not compile with GCC: {result.stderr}'

    with open(rebuilt, 'rb') as f:
        rebuilt_bytes = f.read()
    assert rebuilt_bytes.startswith(b'\x7fELF'), 'GCC did not produce an ELF executable'
    assert b'regcomp' in rebuilt_bytes and b'regexec' in rebuilt_bytes, 'rebuilt C program is not linked to the regex APIs'


def test_config_filter_clean_corpus():
    clean_dir = '/app/corpus/clean'
    assert os.path.isdir(clean_dir), f'Clean corpus directory missing: {clean_dir}'

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, 'Clean corpus directory is empty'

    modified_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, 'rb') as f:
            original_content = f.read()
        result = subprocess.run([BINARY_PATH], input=original_content, capture_output=True)
        if result.returncode != 0 or result.stdout != original_content:
            modified_files.append(filename)

    assert not modified_files, f"{len(modified_files)} of {len(clean_files)} clean files modified. Offending files: {', '.join(modified_files)}"


def test_config_filter_evil_corpus():
    evil_dir = '/app/corpus/evil'
    assert os.path.isdir(evil_dir), f'Evil corpus directory missing: {evil_dir}'

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, 'Evil corpus directory is empty'

    bypassed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            original_text = f.read()
        expected_text = re.sub(r'AKIA[A-Z0-9]{16}', 'AKIA****************', original_text)
        with open(filepath, 'rb') as f:
            original_bytes = f.read()
        result = subprocess.run([BINARY_PATH], input=original_bytes, capture_output=True)
        output_text = result.stdout.decode('utf-8', errors='ignore')
        if result.returncode != 0 or output_text != expected_text:
            bypassed_files.append(filename)

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed. Offending files: {', '.join(bypassed_files)}"


def randomized_payloads():
    alphabet = string.ascii_uppercase + string.digits

    def token():
        return ('AKIA' + ''.join(secrets.choice(alphabet) for _ in range(16))).encode('ascii')

    payloads = [
        b'',
        b'ordinary configuration text\n',
        b'AKIA\nAKIA123\nAKIA1234567890abcdef\nAKIA_1234567890ABCDE\n',
        b'x' * 65531 + token() + b'\nend',
    ]
    for _ in range(30):
        first = token()
        second = token()
        third = token()
        padding1 = secrets.token_hex(secrets.randbelow(40) + 1).encode('ascii')
        padding2 = secrets.token_urlsafe(secrets.randbelow(40) + 1).encode('ascii')
        payloads.append(
            b'prefix=' + padding1 + b'; key:' + first + b'\n'
            + b'unchanged=AKIA' + padding2.lower() + b'\n'
            + b'pair=' + second + b',' + third + b'; suffix=' + padding2 + b'\n'
        )
    return payloads


def test_config_filter_adversarial_generated_inputs():
    rebuilt = '/tmp/config_filter_generated_test'
    result = subprocess.run(['gcc', '-std=c11', SOURCE_PATH, '-o', rebuilt], capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr.decode('utf-8', errors='replace')

    for payload in randomized_payloads():
        expected = re.sub(rb'AKIA[A-Z0-9]{16}', b'AKIA****************', payload)
        assert run_filter(BINARY_PATH, payload) == expected
        assert run_filter(rebuilt, payload) == expected


def expected_report_from_inputs():
    capture = cv2.VideoCapture('/app/config_blinks.mp4')
    assert capture.isOpened(), 'Could not open config_blinks.mp4'
    commit_ids = []
    frame_number = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        # MP4 decoding introduces tiny rounding loss; these are the encoded pure-white frames.
        if np.all(rgb >= 250):
            commit_ids.append(frame_number)
        frame_number += 1
    capture.release()
    assert commit_ids, 'No white commit frames found in the video'

    records = []
    with open('/app/audit_log.csv', 'r', encoding='utf-8') as f:
        header = f.readline().rstrip('\n')
        assert header == 'commit_id,service_name,config_snippet'
        for line in f:
            parts = line.rstrip('\n').split(',', 2)
            assert len(parts) == 3
            commit_id, service_name, snippet = parts
            if int(commit_id) in commit_ids:
                snippet = snippet.replace('\\"', '"')
                snippet = re.sub(r'AKIA[A-Z0-9]{16}', 'AKIA****************', snippet)
                records.append((service_name, commit_id, snippet))

    records.sort(key=lambda item: item[0])
    output = ['# Configuration Audit Report']
    for service_name, commit_id, snippet in records:
        output.extend([
            '',
            f'## Service: {service_name}',
            f'- Commit: {commit_id}',
            f'- Configuration: {snippet}',
        ])
    return '\n'.join(output).strip()


def test_final_report():
    report_path = '/home/user/final_report.md'
    assert os.path.isfile(report_path), f'Final report not found at {report_path}'

    with open(report_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_content = '''# Configuration Audit Report

## Service: auth-service
- Commit: 142
- Configuration: "{ "aws_key": "AKIA****************", "role": "admin" }"

## Service: auth-service
- Commit: 1024
- Configuration: "{ "token": "standard_token", "refresh": false }"

## Service: payment-gateway
- Commit: 512
- Configuration: "key=AKIA****************;mode=prod"
'''.strip()

    assert content == expected_content, 'Final report content does not match the expected output exactly.'
    assert content == expected_report_from_inputs(), 'Final report was not correctly derived from the video and audit log.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
