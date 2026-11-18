#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import pwd
import secrets
import shutil
import stat
import subprocess
from collections import Counter
from pathlib import Path

SCRIPT_PATH = Path('/home/user/audit_policy.sh')
REPORT_PATH = Path('/home/user/audit_report.txt')
HOME = Path('/home/user')


def b64url(value):
    raw = json.dumps(value, separators=(',', ':')).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip('=')


def reset_path(path):
    if os.path.lexists(path):
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)
        else:
            shutil.rmtree(path)


def write_token(path, header, payload):
    path.write_text(f'{b64url(header)}.{b64url(payload)}.signature\n')


def build_fixtures():
    user = pwd.getpwnam('user')
    os.chown(HOME, user.pw_uid, user.pw_gid)
    os.chmod(HOME, 0o755)

    for name in ('tokens', 'logs', 'certs', 'keys'):
        reset_path(HOME / name)
        (HOME / name).mkdir(mode=0o755)

    if os.path.lexists(REPORT_PATH):
        reset_path(REPORT_PATH)

    suffix = secrets.token_hex(6)

    safe_token = f'safe_{suffix}.jwt'
    bad_token_1 = f'unsigned_{suffix}.jwt'
    bad_token_2 = f'legacy_{suffix}.jwt'
    write_token(HOME / 'tokens' / safe_token,
                {'alg': 'HS256', 'typ': 'JWT'}, {'user': 'admin'})
    write_token(HOME / 'tokens' / bad_token_1,
                {'alg': 'none', 'typ': 'JWT'}, {'user': 'guest'})
    write_token(HOME / 'tokens' / bad_token_2,
                {'typ': 'JWT', 'alg': 'none'}, {'user': 'tester'})
    (HOME / 'tokens' / f'malformed_{suffix}.jwt').write_text('not-a-token\n')

    benign_prefix = 1 + secrets.randbelow(3)
    log_lines = [f'127.0.0.1 - GET /safe/{i} 200' for i in range(benign_prefix)]
    xss_line = len(log_lines) + 1
    log_lines.append('192.0.2.10 - GET /search?q=<script>alert(1)</script> 400')
    log_lines.append('127.0.0.1 - GET /health 200')
    sqli_line = len(log_lines) + 1
    log_lines.append('198.51.100.7 - GET /users?id=1 UNION SELECT name,password FROM users 400')
    log_lines.append('127.0.0.1 - GET /literal?value=union-select 200')
    (HOME / 'logs' / 'access.log').write_text('\n'.join(log_lines) + '\n')

    safe_key = HOME / 'keys' / f'owner_only_{suffix}.pem'
    bad_key_1 = HOME / 'keys' / f'world_readable_{suffix}.pem'
    bad_key_2 = HOME / 'keys' / f'executable_{suffix}.pem'
    safe_key.write_text('safe-secret\n')
    bad_key_1.write_text('bad-secret-one\n')
    bad_key_2.write_text('bad-secret-two\n')
    os.chmod(safe_key, 0o600)
    os.chmod(bad_key_1, 0o644)
    os.chmod(bad_key_2, 0o700)

    certs = HOME / 'certs'
    commands = [
        ['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-keyout', str(certs / 'ca.key'),
         '-out', str(certs / 'ca.pem'), '-days', '2', '-nodes', '-subj', '/CN=AuditRoot'],
        ['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-keyout', str(certs / 'other_ca.key'),
         '-out', str(certs / 'other_ca.pem'), '-days', '2', '-nodes', '-subj', '/CN=OtherRoot'],
        ['openssl', 'req', '-newkey', 'rsa:2048', '-keyout', str(certs / 'server.key'),
         '-out', str(certs / 'server.csr'), '-nodes', '-subj', '/CN=localhost'],
        ['openssl', 'x509', '-req', '-in', str(certs / 'server.csr'),
         '-CA', str(certs / 'other_ca.pem'), '-CAkey', str(certs / 'other_ca.key'),
         '-CAcreateserial', '-out', str(certs / 'server.pem'), '-days', '2'],
    ]
    for command in commands:
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)

    for directory in (HOME / 'tokens', HOME / 'logs', HOME / 'certs', HOME / 'keys'):
        os.chmod(directory, 0o755)
        for entry in directory.iterdir():
            if entry.is_file() and entry.parent != HOME / 'keys':
                os.chmod(entry, 0o644)

    return [
        f'JWT_VULN: {bad_token_1}',
        f'JWT_VULN: {bad_token_2}',
        f'INJECTION_VULN: line {xss_line}',
        f'INJECTION_VULN: line {sqli_line}',
        'CERT_VULN: server.pem is invalid',
        f'PERM_VULN: {bad_key_1.name}',
        f'PERM_VULN: {bad_key_2.name}',
    ]


def test_audit_script_exists_and_executable():
    assert SCRIPT_PATH.exists(), f'Audit script {SCRIPT_PATH} does not exist.'
    assert stat.S_ISREG(SCRIPT_PATH.stat().st_mode), f'Audit script {SCRIPT_PATH} is not a regular file.'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Audit script {SCRIPT_PATH} is not executable.'


def test_audit_report_contents():
    expected_lines = build_fixtures()

    result = subprocess.run(
        ['runuser', '-u', 'user', '--', '/bin/bash', str(SCRIPT_PATH)],
        cwd=str(HOME), capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f'Audit script exited with status {result.returncode}. '
        f'stdout={result.stdout!r} stderr={result.stderr!r}'
    )
    assert REPORT_PATH.exists(), f'Audit report {REPORT_PATH} does not exist.'
    assert REPORT_PATH.is_file(), f'Audit report {REPORT_PATH} is not a regular file.'

    with REPORT_PATH.open() as report:
        report_lines = [line.strip() for line in report if line.strip()]

    assert Counter(report_lines) == Counter(expected_lines), (
        f'Report contents differ. Expected {sorted(expected_lines)!r}, '
        f'got {sorted(report_lines)!r}.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
