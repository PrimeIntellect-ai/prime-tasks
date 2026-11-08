#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from urllib.parse import urlsplit

import pytest

EVIL_DIR = '/app/corpus/evil/'
CLEAN_DIR = '/app/corpus/clean/'
BINARY_PATH = '/home/user/waf_filter'


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Binary {BINARY_PATH} does not exist. Did you compile it?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."


def test_waf_filter_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, "Evil corpus is empty."

    bypassed = []
    for f in evil_files:
        filepath = os.path.join(EVIL_DIR, f)
        try:
            result = subprocess.run([BINARY_PATH, filepath], capture_output=True, text=True, timeout=2)
            output = result.stdout.strip()
            if output != "EVIL":
                bypassed.append(f)
        except subprocess.TimeoutExpired:
            bypassed.append(f"{f} (timeout)")

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {bypassed}")


def test_waf_filter_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, "Clean corpus is empty."

    modified = []
    for f in clean_files:
        filepath = os.path.join(CLEAN_DIR, f)
        try:
            result = subprocess.run([BINARY_PATH, filepath], capture_output=True, text=True, timeout=2)
            output = result.stdout.strip()
            if output != "CLEAN":
                modified.append(f)
        except subprocess.TimeoutExpired:
            modified.append(f"{f} (timeout)")

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified: {modified}")


def _encode_all(value, rng):
    encoded = []
    for byte in value.encode('utf-8'):
        digits = f"{byte:02X}"
        digits = ''.join(
            ch.lower() if ch in 'ABCDEF' and rng.randrange(2) else ch
            for ch in digits
        )
        encoded.append('%' + digits)
    return ''.join(encoded)


def _encode_rounds(value, rounds, rng):
    for _ in range(rounds):
        value = _encode_all(value, rng)
    return value


def _expected_for_target(target):
    parsed = urlsplit(target)
    if parsed.scheme.lower() in ('http', 'https') and parsed.hostname:
        if parsed.hostname.lower() not in ('localhost', '127.0.0.1'):
            return 'EVIL'
    return 'CLEAN'


def test_waf_filter_content_based_decoding_on_neutral_path():
    rng = secrets.SystemRandom()
    targets = [
        'http://evil.com',
        'https://EVIL.com/login',
        '/dashboard',
        '/profile',
    ]
    cases = []
    for target in targets:
        expected = _expected_for_target(target)
        for rounds in (0, 1, 2):
            value = _encode_rounds(target, rounds, rng)
            request = (
                f"GET /?redirect={value} HTTP/1.1\r\n"
                f"Host: localhost\r\n"
                f"X-Request-ID: {secrets.token_hex(8)}\r\n\r\n"
            )
            cases.append((request, expected, target, rounds))

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix='waf-input-') as directory:
        # Every case is presented through the exact same neutral path, so the
        # classification must follow the request contents rather than argv.
        filepath = os.path.join(directory, secrets.token_hex(12) + '.req')
        for request, expected, target, rounds in cases:
            with open(filepath, 'w', newline='') as handle:
                handle.write(request)
            try:
                result = subprocess.run(
                    [BINARY_PATH, filepath], capture_output=True, text=True, timeout=2
                )
                output = result.stdout.strip()
                if output != expected:
                    failures.append(
                        f"target={target!r}, rounds={rounds}, expected={expected}, got={output!r}"
                    )
            except subprocess.TimeoutExpired:
                failures.append(
                    f"target={target!r}, rounds={rounds}, expected={expected}, timeout"
                )

    if failures:
        pytest.fail('Generated request classification failures: ' + '; '.join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
