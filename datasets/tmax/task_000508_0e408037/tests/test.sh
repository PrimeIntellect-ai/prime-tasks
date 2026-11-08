#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import uuid

import pytest

RAW_PATH = '/app/traffic.raw'
SANITIZED_PATH = '/home/user/sanitized_traffic.raw'
ALERTS_PATH = '/home/user/alerts.log'
AUDITOR_SOURCE = '/home/user/auditor.cpp'
PICO_DIR = '/app/picohttpparser-2.1'
PICO_SOURCE = os.path.join(PICO_DIR, 'picohttpparser.c')
TOKEN = b'X9fK_master_2024'
REDACTION = b'[REDACTED]'
AUDITOR_BIN = '/tmp/auditor-under-test'


def run_checked(args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


@pytest.fixture(scope='session', autouse=True)
def build_submission():
    assert os.path.isfile(AUDITOR_SOURCE), f'C++ source missing: {AUDITOR_SOURCE}'
    assert os.path.isfile(PICO_SOURCE), f'picohttpparser.c missing: {PICO_SOURCE}'

    with open(PICO_SOURCE, 'r', encoding='utf-8', errors='replace') as f:
        pico_content = f.read()
    assert '<string.h>' in pico_content, (
        "The typo '<sting.h>' was not fixed to '<string.h>' in picohttpparser.c"
    )

    # Compile the repaired C parser as C, then compile the submitted program as C++.
    run_checked(['gcc', '-std=c99', '-c', PICO_SOURCE, '-I', PICO_DIR,
                 '-o', '/tmp/picohttpparser.o'])
    run_checked(['g++', '-std=c++17', '-c', AUDITOR_SOURCE, '-I', PICO_DIR,
                 '-o', '/tmp/auditor.o'])

    # Ensure the C++ translation unit actually calls the vendored request parser.
    nm = run_checked(['nm', '/tmp/auditor.o'], text=True).stdout
    assert re.search(r'^\s*U\s+phr_parse_request\s*$', nm, re.MULTILINE), (
        'auditor.cpp does not reference picohttpparser phr_parse_request'
    )

    run_checked(['g++', '/tmp/auditor.o', '/tmp/picohttpparser.o',
                 '-o', AUDITOR_BIN])
    assert os.path.isfile(AUDITOR_BIN) and os.access(AUDITOR_BIN, os.X_OK)


def execute_with_traffic(traffic):
    with open(RAW_PATH, 'rb') as f:
        original = f.read()
    try:
        with open(RAW_PATH, 'wb') as f:
            f.write(traffic)
        for path in (SANITIZED_PATH, ALERTS_PATH):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        run_checked([AUDITOR_BIN], timeout=10)

        assert os.path.isfile(SANITIZED_PATH), (
            f'Sanitized traffic file missing: {SANITIZED_PATH}'
        )
        assert os.path.isfile(ALERTS_PATH), f'Alerts log file missing: {ALERTS_PATH}'
        with open(SANITIZED_PATH, 'rb') as f:
            sanitized = f.read()
        with open(ALERTS_PATH, 'rb') as f:
            alerts = f.read()
        return sanitized, alerts
    finally:
        with open(RAW_PATH, 'wb') as f:
            f.write(original)


def test_picohttpparser_fixed():
    # The session build compiled picohttpparser.c successfully; retain the
    # original source-level assertion as well.
    assert os.path.isfile(PICO_SOURCE), f'picohttpparser.c missing: {PICO_SOURCE}'
    with open(PICO_SOURCE, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    assert '<string.h>' in content, (
        "The typo '<sting.h>' was not fixed to '<string.h>' in picohttpparser.c"
    )


def test_sanitized_traffic_f1_score_and_reconstruction():
    assert os.path.isfile(RAW_PATH), f'Raw traffic file missing: {RAW_PATH}'
    with open(RAW_PATH, 'rb') as f:
        raw = f.read()

    sanitized, alerts = execute_with_traffic(raw)
    original_count = raw.count(TOKEN)
    remnant_count = sanitized.count(TOKEN)
    redacted_count = sanitized.count(REDACTION)

    if original_count == 0 or remnant_count > 0:
        f1_score = 0.0
    elif redacted_count != original_count:
        f1_score = redacted_count / original_count
    else:
        f1_score = 1.0

    assert f1_score >= 0.99, (
        f'Redaction F1-Score {f1_score} is below threshold 0.99. '
        f'remnant_count={remnant_count}, redacted_count={redacted_count}, '
        f'original_count={original_count}'
    )
    assert sanitized == raw.replace(TOKEN, REDACTION), (
        'Sanitized traffic was not an exact reconstruction of the input with '
        'only master-token instances replaced'
    )
    assert b'UNAUTHORIZED: ' in alerts, (
        "Alerts log missing expected 'UNAUTHORIZED: ' string format"
    )
    assert alerts == b'UNAUTHORIZED: /admin\n', (
        f'Incorrect alerts for supplied traffic: {alerts!r}'
    )


def test_generated_traffic_preservation_redaction_and_alerts():
    marker = uuid.uuid4().hex.encode('ascii')
    similar = b'X9fK_master_2025_' + marker
    traffic = (
        b'GET /admin HTTP/1.1\r\n'
        b'Host: host-' + marker + b'\r\n'
        b'Authorization: Bearer ' + TOKEN + b'\r\n'
        b'X-Preserve: [REDACTED]-' + similar + b'\r\n\r\n'
        b'GET /public HTTP/1.1\r\n'
        b'Host: public-' + marker + b'\r\n'
        b'Cookie: before=' + TOKEN + b'; after=' + TOKEN + b'\r\n\r\n'
        b'GET /admin HTTP/1.1\r\n'
        b'Host: denied-one-' + marker + b'\r\n'
        b'Authorization: Bearer ' + similar + b'\r\n\r\n'
        b'POST /admin HTTP/1.1\r\n'
        b'Host: denied-two-' + marker + b'\r\n'
        b'Cookie: session=ordinary-' + marker + b'\r\n'
        b'Content-Length: 0\r\n\r\n'
        b'GET /not-admin HTTP/1.1\r\n'
        b'Host: final-' + marker + b'\r\n\r\n'
    )

    sanitized, alerts = execute_with_traffic(traffic)
    expected = traffic.replace(TOKEN, REDACTION)

    assert sanitized == expected, (
        'Generated traffic was not preserved byte-for-byte apart from exact '
        'master-token redactions'
    )
    assert TOKEN not in sanitized
    assert similar in sanitized, 'Similar non-token text was falsely redacted'
    assert marker in sanitized, 'Unrelated traffic content was not preserved'
    assert sanitized.count(REDACTION) == traffic.count(TOKEN) + 1, (
        'Existing redaction text or required token replacements were altered'
    )
    assert b'UNAUTHORIZED: ' in alerts
    assert alerts == b'UNAUTHORIZED: /admin\nUNAUTHORIZED: /admin\n', (
        f'Incorrect generated-traffic alerts: {alerts!r}'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
