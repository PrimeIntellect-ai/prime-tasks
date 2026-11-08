#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import stat
import subprocess

AUTH_LOG = b'''{"ip": "192.168.1.10", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhbGljZSJ9.signature1"}
{"ip": "10.0.0.5", "token": "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhZG1pbl9iYWNrZG9vciJ9."}
{"ip": "192.168.1.11", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJib2IifQ.signature2"}
{"ip": "10.0.0.6", "token": "eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJzdWIiOiJzeXN0ZW1fZGFlbW9uIn0."}
{"ip": "192.168.1.12", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjaGFybGllIn0.signature3"}
'''

EXPECTED_FILES = {
    '/home/user/ssh_keys/id_rsa': (0o600, b''),
    '/home/user/ssh_keys/id_ed25519': (0o644, b''),
    '/home/user/ssh_keys/id_ecdsa': (0o660, b''),
    '/home/user/ssh_keys/public_key.pub': (0o644, b''),
    '/home/user/scripts/backup.sh': (0o755, b'#!/bin/bash\ntar -czf /tmp/backup.tar.gz /home/user\n'),
    '/home/user/scripts/cleanup.sh': (0o777, b'#!/bin/bash\nrm -rf /tmp/cache/*\n'),
}


def assert_regular_file(path):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f'{path} is not a regular file'
    assert not os.path.islink(path), f'{path} must not be a symlink'
    return st


def assert_original_inputs():
    assert_regular_file('/home/user/auth_logs.jsonl')
    with open('/home/user/auth_logs.jsonl', 'rb') as f:
        assert f.read() == AUTH_LOG, 'Authentication log was altered'

    assert os.path.isdir('/home/user/ssh_keys') and not os.path.islink('/home/user/ssh_keys')
    assert set(os.listdir('/home/user/ssh_keys')) == {
        'id_rsa', 'id_ed25519', 'id_ecdsa', 'public_key.pub'
    }, 'SSH key audit inputs were altered'

    assert os.path.isdir('/home/user/scripts') and not os.path.islink('/home/user/scripts')
    assert set(os.listdir('/home/user/scripts')) == {'backup.sh', 'cleanup.sh'}, \
        'Script audit inputs were altered'

    for path, (mode, content) in EXPECTED_FILES.items():
        st = assert_regular_file(path)
        assert stat.S_IMODE(st.st_mode) == mode, f'Permissions changed for {path}'
        with open(path, 'rb') as f:
            assert f.read() == content, f'Contents changed for {path}'


def decode_base64_url(s):
    s = s + '=' * (-len(s) % 4)
    s = s.replace('-', '+').replace('_', '/')
    return base64.b64decode(s).decode('utf-8')


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f.read().strip().split('\n') if line.strip()]


def encode_part(value):
    raw = json.dumps(value, separators=(',', ':')).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip('=')


def token(alg, sub):
    return f'{encode_part({"alg": alg, "typ": "JWT"})}.{encode_part({"sub": sub})}.'


def test_00_original_audit_inputs_are_intact():
    assert_original_inputs()


def test_01_required_jwt_analyzer_executes_and_processes_logs():
    script = '/home/user/analyze_jwt.py'
    assert os.path.exists(script), f'Required script {script} does not exist'
    assert_regular_file(script)

    challenge = [
        {'token': token('none', 'zeta')},
        {'token': token('HS256', 'ignored')},
        {'token': token('NoNe', 'alpha')},
        {'token': token('NONE', 'zeta')},
        {'token': 'malformed-token'},
        {'other': 'missing token'},
    ]
    challenge_bytes = ''.join(json.dumps(row) + '\n' for row in challenge).encode()

    try:
        with open('/home/user/auth_logs.jsonl', 'wb') as f:
            f.write(challenge_bytes)
        result = subprocess.run(
            ['python3', script], cwd='/home/user', capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, \
            f'analyze_jwt.py failed: stdout={result.stdout!r}, stderr={result.stderr!r}'
        assert os.path.isfile('/home/user/compromised_subs.txt')
        assert read_nonempty_lines('/home/user/compromised_subs.txt') == ['alpha', 'zeta']
    finally:
        with open('/home/user/auth_logs.jsonl', 'wb') as f:
            f.write(AUTH_LOG)

    result = subprocess.run(
        ['python3', script], cwd='/home/user', capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, \
        f'analyze_jwt.py failed on the supplied log: {result.stderr!r}'


def test_02_inputs_remain_intact_after_analyzer_execution():
    assert_original_inputs()


def test_phase1_jwt_analysis():
    log_file = '/home/user/auth_logs.jsonl'
    output_file = '/home/user/compromised_subs.txt'
    assert os.path.isfile(output_file), f'Output file {output_file} does not exist.'

    expected_subs = set()
    with open(log_file, 'r') as f:
        for line in f:
            try:
                data = json.loads(line)
                token_value = data.get('token', '')
                parts = token_value.split('.')
                if len(parts) >= 2:
                    header = json.loads(decode_base64_url(parts[0]))
                    if header.get('alg', '').lower() == 'none':
                        payload = json.loads(decode_base64_url(parts[1]))
                        if 'sub' in payload:
                            expected_subs.add(payload['sub'])
            except Exception:
                continue

    expected_sorted = sorted(list(expected_subs))
    actual_lines = read_nonempty_lines(output_file)
    assert actual_lines == expected_sorted, \
        f'Expected compromised subjects {expected_sorted}, but got {actual_lines}'


def test_phase2_ssh_key_audit():
    keys_dir = '/home/user/ssh_keys'
    output_file = '/home/user/weak_ssh_keys.txt'
    assert os.path.isfile(output_file), f'Output file {output_file} does not exist.'

    expected_weak_keys = []
    if os.path.isdir(keys_dir):
        for filename in os.listdir(keys_dir):
            if filename.startswith('id_'):
                filepath = os.path.join(keys_dir, filename)
                if os.path.isfile(filepath):
                    perms = stat.S_IMODE(os.stat(filepath).st_mode)
                    if perms & 0o077 != 0:
                        expected_weak_keys.append(filepath)

    expected_sorted = sorted(expected_weak_keys)
    actual_lines = read_nonempty_lines(output_file)
    assert actual_lines == expected_sorted, \
        f'Expected weak SSH keys {expected_sorted}, but got {actual_lines}'


def test_phase3_privesc_auditing():
    scripts_dir = '/home/user/scripts'
    output_file = '/home/user/privesc_vuln.txt'
    assert os.path.isfile(output_file), f'Output file {output_file} does not exist.'

    expected_lines = []
    if os.path.isdir(scripts_dir):
        for filename in os.listdir(scripts_dir):
            filepath = os.path.join(scripts_dir, filename)
            if os.path.isfile(filepath):
                st = os.stat(filepath)
                if st.st_mode & stat.S_IWOTH:
                    hasher = hashlib.sha256()
                    with open(filepath, 'rb') as f:
                        for chunk in iter(lambda: f.read(4096), b''):
                            hasher.update(chunk)
                    expected_lines.append(f'{hasher.hexdigest()}  {filepath}')

    actual_lines = read_nonempty_lines(output_file)
    actual_standardized = [' '.join(line.split()) for line in actual_lines]
    expected_standardized = [' '.join(line.split()) for line in expected_lines]
    assert actual_standardized == expected_standardized, \
        f'Expected privesc output {expected_standardized}, but got {actual_standardized}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
