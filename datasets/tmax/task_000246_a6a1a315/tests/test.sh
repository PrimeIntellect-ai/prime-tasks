#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import urllib.parse
from pathlib import Path

HOME = Path('/home/user')
SOURCE = HOME / 'analyze.go'
TRAFFIC = HOME / 'traffic.jsonl'
PROCESSED = HOME / 'processed_traffic.jsonl'
BINARY = HOME / 'server_bin'
EXECUTABLE = Path('/tmp/analyze_submission')


def get_binary_strings(filepath):
    """Extracts the configuration strings from the binary."""
    with open(filepath, 'rb') as f:
        content = f.read()

    trusted_domain_match = re.search(b'TRUSTED_DOMAIN=([a-zA-Z0-9.-]+)', content)
    secret_cookie_match = re.search(b'SECRET_COOKIE_NAME=([a-zA-Z0-9_.-]+)', content)

    trusted_domain = trusted_domain_match.group(1).decode('utf-8') if trusted_domain_match else 'secure.internal.corp'
    secret_cookie = secret_cookie_match.group(1).decode('utf-8') if secret_cookie_match else 'Admin_X_Session_Token'
    return trusted_domain, secret_cookie


def build_and_run():
    assert SOURCE.exists(), f'{SOURCE} does not exist.'
    assert SOURCE.is_file(), f'{SOURCE} is not a regular file.'
    if EXECUTABLE.exists():
        EXECUTABLE.unlink()
    built = subprocess.run(
        ['go', 'build', '-o', str(EXECUTABLE), str(SOURCE)],
        cwd=str(HOME), capture_output=True, text=True, timeout=45
    )
    assert built.returncode == 0, f'analyze.go did not compile:\n{built.stdout}\n{built.stderr}'
    assert EXECUTABLE.is_file(), 'Go build did not produce an executable.'
    if PROCESSED.exists():
        PROCESSED.unlink()
    ran = subprocess.run(
        [str(EXECUTABLE)], cwd=str(HOME), capture_output=True, text=True, timeout=20
    )
    assert ran.returncode == 0, f'analyze.go execution failed:\n{ran.stdout}\n{ran.stderr}'


def parse_jsonl(path):
    assert path.exists(), f'Output file {path} does not exist. Did you run your Go program?'
    assert path.is_file(), f'{path} is not a file.'
    text = path.read_text()
    assert text.strip(), f'File {path} is empty.'
    lines = text.splitlines()
    assert all(line.strip() for line in lines), f'{path} contains a blank JSONL line.'
    records = []
    for i, line in enumerate(lines):
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f'Line {i + 1} in {path} is not valid JSON: {exc}')
        assert isinstance(value, dict), f'Line {i + 1} is not a JSON object.'
        records.append(value)
    return records


def redact_cookie(cookie, secret_cookie):
    parts = cookie.split(';')
    result = []
    for part in parts:
        leading = part[:len(part) - len(part.lstrip())]
        body = part.lstrip()
        if '=' in body:
            name, value = body.split('=', 1)
            if name.strip() == secret_cookie:
                part = leading + name + '=[REDACTED]'
        result.append(part)
    return ';'.join(result)


def expected_record(record, trusted_domain, secret_cookie):
    expected = json.loads(json.dumps(record))
    headers = expected.get('headers', {})
    if 'Cookie' in headers:
        headers['Cookie'] = redact_cookie(headers['Cookie'], secret_cookie)

    redirect_values = urllib.parse.parse_qs(
        urllib.parse.urlsplit(expected.get('url', '')).query,
        keep_blank_values=True
    ).get('redirect')
    attempt = False
    if redirect_values:
        host = urllib.parse.urlsplit(redirect_values[0]).hostname
        attempt = host != trusted_domain
    expected['open_redirect_attempt'] = attempt
    expected['injected_csp'] = (
        "default-src 'self'; frame-ancestors 'none'; connect-src https://"
        + trusted_domain
    )
    return expected


def validate_complete_transformation(inputs, outputs, trusted_domain, secret_cookie):
    assert len(outputs) == len(inputs), 'Output must contain exactly one JSON object per input line.'
    expected = [expected_record(r, trusted_domain, secret_cookie) for r in inputs]
    assert outputs == expected, (
        'Output records must remain in input order and preserve request_id, method, url, '
        'all unmodified headers, and all other fields while applying only the required transformations.'
    )


def test_complete_program_behavior():
    trusted_domain, secret_cookie = get_binary_strings(BINARY)
    expected_csp = f"default-src 'self'; frame-ancestors 'none'; connect-src https://{trusted_domain}"
    original_traffic = TRAFFIC.read_bytes()
    prior_output = PROCESSED.read_bytes() if PROCESSED.exists() and PROCESSED.is_file() else None
    restored_output = prior_output

    try:
        original_inputs = parse_jsonl(TRAFFIC)
        build_and_run()

        # Keep the original verifier's existence and fixed-record assertions.
        assert PROCESSED.exists(), f'Output file {PROCESSED} does not exist. Did you run your Go program?'
        assert PROCESSED.is_file(), f'{PROCESSED} is not a file.'
        outputs = parse_jsonl(PROCESSED)
        assert len(outputs) > 0, f'File {PROCESSED} is empty.'

        records = {}
        for data in outputs:
            req_id = data.get('request_id')
            if req_id:
                records[req_id] = data

        assert 'req-001' in records, 'req-001 is missing from the processed output.'
        assert 'req-002' in records, 'req-002 is missing from the processed output.'
        assert 'req-003' in records, 'req-003 is missing from the processed output.'

        req1 = records['req-001']
        assert req1.get('open_redirect_attempt') is False, 'req-001 should have open_redirect_attempt as false.'
        cookie1 = req1.get('headers', {}).get('Cookie', '')
        assert f'{secret_cookie}=[REDACTED]' in cookie1, f'req-001 Cookie does not have {secret_cookie} redacted.'
        assert 'user_pref=dark' in cookie1, 'req-001 Cookie is missing other unmodified cookies.'
        assert req1.get('injected_csp') == expected_csp, f'req-001 injected_csp is incorrect. Expected: {expected_csp}'

        req2 = records['req-002']
        assert req2.get('open_redirect_attempt') is True, 'req-002 should have open_redirect_attempt as true (evil-phishing.com).'
        cookie2 = req2.get('headers', {}).get('Cookie', '')
        assert 'session=normaluser' in cookie2, 'req-002 Cookie should remain unmodified.'
        assert req2.get('injected_csp') == expected_csp, f'req-002 injected_csp is incorrect. Expected: {expected_csp}'

        req3 = records['req-003']
        assert req3.get('open_redirect_attempt') is False, 'req-003 should have open_redirect_attempt as false (no redirect).'
        cookie3 = req3.get('headers', {}).get('Cookie', '')
        assert cookie3 == f'{secret_cookie}=[REDACTED]', f'req-003 Cookie should be exactly {secret_cookie}=[REDACTED].'
        assert req3.get('injected_csp') == expected_csp, f'req-003 injected_csp is incorrect. Expected: {expected_csp}'

        validate_complete_transformation(original_inputs, outputs, trusted_domain, secret_cookie)
        restored_output = PROCESSED.read_bytes()

        # Replace the input with unpredictable records and execute the submitted program again.
        token = secrets.token_hex(12)
        evil = f'{token}.attacker.example'
        dynamic_inputs = [
            {
                'request_id': f'dyn-{token}-1', 'method': 'GET',
                'url': '/login?' + urllib.parse.urlencode({'redirect': f'https://{trusted_domain}/admin'}),
                'headers': {'Cookie': f'{secret_cookie}={token}; theme=dark', 'User-Agent': f'agent-{token}', 'X-Trace': token}
            },
            {
                'request_id': f'dyn-{token}-2', 'method': 'POST',
                'url': '/login?' + urllib.parse.urlencode({'redirect': f'https://{evil}/steal'}),
                'headers': {'Cookie': f'session={token}', 'User-Agent': 'dynamic-client', 'X-Trace': token[::-1]}
            },
            {
                'request_id': f'dyn-{token}-3', 'method': 'PUT',
                'url': '/continue?' + urllib.parse.urlencode({'redirect': f'https://{trusted_domain}.{evil}/path'}),
                'headers': {'Cookie': f'first=1; {secret_cookie}={token}; last=2', 'User-Agent': 'preserve-me'}
            },
            {
                'request_id': f'dyn-{token}-4', 'method': 'DELETE', 'url': '/login',
                'headers': {'Cookie': f'{secret_cookie}_backup={token}; ordinary=yes', 'User-Agent': token}
            },
            {
                'request_id': f'dyn-{token}-5', 'method': 'PATCH',
                'url': '/login?' + urllib.parse.urlencode({'redirect': f'http://{trusted_domain}/ok', 'state': token}),
                'headers': {'Cookie': f'a=1; {secret_cookie}={token}', 'User-Agent': 'ua', 'X-Custom': f'value-{token}'}
            },
            {
                'request_id': f'dyn-{token}-6', 'method': 'GET',
                'url': '/login?' + urllib.parse.urlencode({'redirect': f'https://not-{trusted_domain}/bad'}),
                'headers': {'User-Agent': f'no-cookie-{token}', 'Accept': 'application/json'}
            }
        ]
        TRAFFIC.write_text(''.join(json.dumps(r, separators=(',', ':')) + '\n' for r in dynamic_inputs))
        build_and_run()
        dynamic_outputs = parse_jsonl(PROCESSED)
        validate_complete_transformation(dynamic_inputs, dynamic_outputs, trusted_domain, secret_cookie)
    finally:
        TRAFFIC.write_bytes(original_traffic)
        if restored_output is not None:
            PROCESSED.write_bytes(restored_output)
        elif PROCESSED.exists():
            PROCESSED.unlink()
        if EXECUTABLE.exists():
            EXECUTABLE.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
