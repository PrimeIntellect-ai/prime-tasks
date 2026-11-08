#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import string
import subprocess
from pathlib import Path

import pytest
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding

BASE = Path('/home/user/audit_trail')
REPORT = BASE / 'compliance_report.json'
INPUTS = [BASE / 'private.pem', BASE / 'symmetric.enc', BASE / 'logs.enc', BASE / 'sudoers_backup']


def derive_expected():
    private_key = serialization.load_pem_private_key(
        (BASE / 'private.pem').read_bytes(), password=None
    )
    fernet_key = private_key.decrypt(
        (BASE / 'symmetric.enc').read_bytes(), padding.PKCS1v15()
    )
    plaintext = Fernet(fernet_key).decrypt((BASE / 'logs.enc').read_bytes())

    sql_count = 0
    xss_count = 0
    for line in plaintext.decode('utf-8').splitlines():
        if not line.strip():
            continue
        entry = json.loads(line)
        payload = entry['payload']
        if "' OR '1'='1" in payload or 'UNION SELECT' in payload:
            sql_count += 1
        if '<script>' in payload:
            xss_count += 1

    users = []
    for raw_line in (BASE / 'sudoers_backup').read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        if re.search(r'NOPASSWD\s*:\s*ALL(?:\s|$)', line):
            user = line.split()[0]
            if user != 'root':
                users.append(user)

    return {
        'sql_injection_count': sql_count,
        'xss_count': xss_count,
        'critical_sudo_users': sorted(users),
    }


def read_report():
    assert REPORT.is_file(), f'The compliance report was not found at {REPORT}.'
    try:
        with REPORT.open('r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'The file at {REPORT} does not contain valid JSON.')
    except Exception as e:
        pytest.fail(f'Failed to read {REPORT}: {e}')


def python_candidates():
    roots = [Path('/home/user'), Path('/home/oai/share'), Path('/root'), Path('/tmp'), Path('/workspace')]
    excluded_dirs = {'.cache', '.local', '__pycache__', 'site-packages', '.git'}
    seen = set()
    result = []
    for root in roots:
        if not root.exists():
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in excluded_dirs]
            for name in files:
                path = Path(current) / name
                try:
                    resolved = path.resolve()
                    if resolved in seen or resolved == Path('/tmp/test_final_state.py'):
                        continue
                    seen.add(resolved)
                    if name.endswith('.py'):
                        result.append(path)
                        continue
                    with path.open('rb') as f:
                        first = f.readline(256).lower()
                    if first.startswith(b'#!') and b'python' in first:
                        result.append(path)
                except (OSError, UnicodeError):
                    continue
    return result


def install_challenge():
    private_key = serialization.load_pem_private_key(
        (BASE / 'private.pem').read_bytes(), password=None
    )
    fernet_key = Fernet.generate_key()
    (BASE / 'symmetric.enc').write_bytes(
        private_key.public_key().encrypt(fernet_key, padding.PKCS1v15())
    )

    sql_count = secrets.randbelow(4) + 1
    xss_count = secrets.randbelow(4) + 1
    logs = []
    for i in range(sql_count):
        trigger = "name' OR '1'='1" if i % 2 == 0 else '1 UNION SELECT secret FROM accounts'
        logs.append({'timestamp': f'2026-01-01T00:00:{i:02d}', 'path': '/query', 'payload': trigger})
    for i in range(xss_count):
        logs.append({'timestamp': f'2026-01-02T00:00:{i:02d}', 'path': '/comment', 'payload': f'<script>alert({i})</script>'})
    logs.extend([
        {'timestamp': '2026-01-03T00:00:00', 'path': '/', 'payload': 'ordinary request'},
        {'timestamp': '2026-01-03T00:00:01', 'path': '/', 'payload': "'; DROP TABLE t;--"},
    ])
    secrets.SystemRandom().shuffle(logs)
    plaintext = '\n'.join(json.dumps(item) for item in logs).encode('utf-8')
    (BASE / 'logs.enc').write_bytes(Fernet(fernet_key).encrypt(plaintext))

    alphabet = string.ascii_lowercase
    names = sorted({''.join(secrets.choice(alphabet) for _ in range(10)) for _ in range(4)})
    while len(names) < 4:
        names = sorted(set(names) | {''.join(secrets.choice(alphabet) for _ in range(10))})
    critical = sorted(names[:3])
    sudoers = [
        '# User privilege specification',
        'root ALL=(ALL:ALL) NOPASSWD: ALL',
        f'{critical[0]} ALL=(ALL) NOPASSWD: ALL',
        f'# {names[3]} ALL=(ALL) NOPASSWD: ALL',
        f'{critical[1]} ALL=(ALL:ALL) NOPASSWD: ALL',
        f'{critical[2]} ALL=(ALL) NOPASSWD: ALL',
        'limited_user ALL=(ALL) /bin/ls',
    ]
    (BASE / 'sudoers_backup').write_text('\n'.join(sudoers), encoding='utf-8')
    return {
        'sql_injection_count': sql_count,
        'xss_count': xss_count,
        'critical_sudo_users': critical,
    }


def run_script(path):
    try:
        return subprocess.run(
            ['python3', str(path)],
            cwd=str(path.parent),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def test_compliance_report_exists_and_valid():
    original_inputs = {path: path.read_bytes() for path in INPUTS}
    original_report = REPORT.read_bytes() if REPORT.exists() else None
    candidates = python_candidates()
    successful_script = None

    try:
        for candidate in candidates:
            for path, content in original_inputs.items():
                path.write_bytes(content)
            expected_challenge = install_challenge()
            if REPORT.exists():
                REPORT.unlink()
            result = run_script(candidate)
            if result is None or result.returncode != 0 or not REPORT.is_file():
                continue
            try:
                challenge_report = json.loads(REPORT.read_text(encoding='utf-8'))
            except Exception:
                continue
            if challenge_report == expected_challenge:
                successful_script = candidate
                break
    finally:
        for path, content in original_inputs.items():
            path.write_bytes(content)
        if original_report is None:
            if REPORT.exists():
                REPORT.unlink()
        else:
            REPORT.write_bytes(original_report)

    assert successful_script is not None, (
        'No submitted Python program regenerated the report from a fresh encrypted '
        'log/key fixture and sudoers file.'
    )

    expected_from_files = derive_expected()
    if REPORT.exists():
        REPORT.unlink()
    result = run_script(successful_script)
    assert result is not None and result.returncode == 0, 'The submitted Python program failed on the provided audit files.'

    data = read_report()
    assert data == expected_from_files, 'The report does not match values derived from the encrypted logs and sudoers backup.'

    # Preserve the original verifier's structure and value assertions.
    assert 'sql_injection_count' in data, "The report is missing the 'sql_injection_count' field."
    assert data['sql_injection_count'] == 2, f"Expected 2 SQL injection occurrences, found {data['sql_injection_count']}."

    assert 'xss_count' in data, "The report is missing the 'xss_count' field."
    assert data['xss_count'] == 2, f"Expected 2 XSS occurrences, found {data['xss_count']}."

    assert 'critical_sudo_users' in data, "The report is missing the 'critical_sudo_users' field."
    expected_users = ['dev_lead', 'ops_manager']
    actual_users = data['critical_sudo_users']
    assert isinstance(actual_users, list), "The 'critical_sudo_users' field must be a list."
    assert actual_users == expected_users, f'Expected critical sudo users {expected_users}, found {actual_users}. Make sure the list is sorted alphabetically.'
    assert set(data) == {'sql_injection_count', 'xss_count', 'critical_sudo_users'}, 'The report does not have the exact required structure.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
