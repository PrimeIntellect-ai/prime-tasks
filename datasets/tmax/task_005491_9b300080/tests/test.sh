#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import base64
import hmac
import hashlib
import secrets
import subprocess

ANALYZER = '/home/user/analyzer.cpp'
EXECUTABLE = '/tmp/analyzer_submission'
REPORT = '/home/user/report.txt'
ELF_PATH = '/home/user/audit_data/auth_daemon'
LOG_PATH = '/home/user/audit_data/requests.log'


def decode_b64url(data):
    pad = len(data) % 4
    if pad:
        data += '=' * (4 - pad)
    return base64.urlsafe_b64decode(data)


def extract_secret_from_elf(filepath):
    with open(filepath, 'rb') as f:
        content = f.read()
    match = re.search(b'KEY_MATERIAL_([^\x00]+)\x00', content)
    if match:
        return match.group(1).decode('utf-8')
    return None


def analyze_logs(log_path, secret_key):
    with open(log_path, 'r') as f:
        content = f.read()

    tokens = re.findall(r'session_token=([a-zA-Z0-9_\-\.]+)', content)
    forged_count = 0
    admin_pin = None

    for token in tokens:
        parts = token.split('.')
        if len(parts) < 2:
            continue

        try:
            header = json.loads(decode_b64url(parts[0]).decode('utf-8'))
            payload = json.loads(decode_b64url(parts[1]).decode('utf-8'))
        except Exception:
            continue

        alg = header.get('alg', '').lower()
        if alg == 'none':
            forged_count += 1
        elif alg == 'hs256' and len(parts) == 3 and secret_key:
            msg = f'{parts[0]}.{parts[1]}'
            expected_sig = base64.urlsafe_b64encode(
                hmac.new(secret_key.encode(), msg.encode(), hashlib.sha256).digest()
            ).decode('utf-8').rstrip('=')

            if parts[2] == expected_sig and payload.get('user') == 'admin':
                pin_hash = payload.get('pin_hash')
                if pin_hash:
                    for i in range(10000):
                        pin = f'{i:04d}'
                        if hashlib.md5(pin.encode()).hexdigest() == pin_hash:
                            admin_pin = pin
                            break

    return forged_count, admin_pin


def file_hash(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def encode_b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).decode('ascii').rstrip('=')


def create_jwt(header, payload, secret=None):
    header_part = encode_b64url(json.dumps(header))
    payload_part = encode_b64url(json.dumps(payload))
    message = f'{header_part}.{payload_part}'
    if secret is None:
        return message + '.'
    signature = hmac.new(secret.encode(), message.encode(), hashlib.sha256).digest()
    return message + '.' + encode_b64url(signature)


def run_and_verify_case():
    assert os.path.isfile(ELF_PATH), 'auth_daemon binary is missing for verification'
    assert os.path.isfile(LOG_PATH), 'requests.log is missing for verification'

    expected_secret = extract_secret_from_elf(ELF_PATH)
    assert expected_secret is not None, 'Could not extract secret from auth_daemon for verification'

    expected_forged, expected_pin = analyze_logs(LOG_PATH, expected_secret)
    assert expected_pin is not None, 'Could not determine expected admin PIN for verification'

    input_hashes = (file_hash(ELF_PATH), file_hash(LOG_PATH))
    if os.path.lexists(REPORT):
        os.remove(REPORT)

    result = subprocess.run(
        [EXECUTABLE], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert result.returncode == 0, (
        f'analyzer exited with status {result.returncode}: {result.stderr}'
    )
    assert input_hashes == (file_hash(ELF_PATH), file_hash(LOG_PATH)), (
        'analyzer must not modify the supplied auth_daemon or requests.log'
    )

    assert os.path.isfile(REPORT), (
        '/home/user/report.txt does not exist. The C++ program must generate this file.'
    )

    with open(REPORT, 'r') as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) == 3, f'Expected exactly 3 lines in report.txt, found {len(lines)}'
    assert lines[0] == expected_secret, (
        f'Line 1 (secret key) is incorrect. Expected {expected_secret}, got {lines[0]}'
    )
    assert lines[1] == str(expected_forged), (
        f'Line 2 (forged count) is incorrect. Expected {expected_forged}, got {lines[1]}'
    )
    assert lines[2] == expected_pin, (
        f'Line 3 (admin PIN) is incorrect. Expected {expected_pin}, got {lines[2]}'
    )


def install_dynamic_case():
    secret = 'dyn' + secrets.token_hex(8)
    while True:
        pin = f'{secrets.randbelow(10000):04d}'
        if pin != '5678':
            break

    source = f'''#include <stdio.h>\nstatic const char key[] __attribute__((used)) = "KEY_MATERIAL_{secret}";\nint main(void) {{ puts("Daemon running..."); return key[0] == 0; }}\n'''
    with open('/tmp/dynamic_auth_daemon.c', 'w') as f:
        f.write(source)
    subprocess.run(
        ['gcc', '/tmp/dynamic_auth_daemon.c', '-o', ELF_PATH],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    os.chmod(ELF_PATH, 0o755)

    pin_hash = hashlib.md5(pin.encode()).hexdigest()
    tokens = [
        create_jwt({'alg': 'HS256', 'typ': 'JWT'},
                   {'user': 'admin', 'pin_hash': pin_hash}, secret),
        create_jwt({'alg': 'HS256', 'typ': 'JWT'},
                   {'user': 'guest', 'pin_hash': hashlib.md5(b'0000').hexdigest()}, secret),
        create_jwt({'alg': 'HS256', 'typ': 'JWT'},
                   {'user': 'admin', 'pin_hash': hashlib.md5(b'1111').hexdigest()},
                   'incorrect-signing-key'),
    ]

    forged_count = secrets.choice([1, 2, 4, 5])
    variants = ['none', 'None', 'NONE', 'nOnE']
    for i in range(forged_count):
        tokens.append(create_jwt({'alg': variants[i % len(variants)], 'typ': 'JWT'},
                                 {'user': 'admin', 'role': 'superuser'}))

    request_template = (
        'GET /api/data HTTP/1.1\n'
        'Host: example.com\n'
        'User-Agent: Mozilla/5.0\n'
        'Cookie: session_token={token}\n'
        'Accept: */*\n\n'
    )
    with open(LOG_PATH, 'w') as f:
        for token in tokens:
            f.write(request_template.format(token=token))
        f.write('GET /index.html HTTP/1.1\nHost: example.com\n\n')


def test_analyzer_compiles_runs_and_analyzes_inputs():
    assert os.path.isfile(ANALYZER), '/home/user/analyzer.cpp does not exist'
    assert not os.path.islink(ANALYZER), '/home/user/analyzer.cpp must be a source file, not a symlink'

    compile_result = subprocess.run(
        ['g++', '-std=c++17', ANALYZER, '-o', EXECUTABLE, '-lcrypto'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert compile_result.returncode == 0, (
        f'analyzer.cpp failed to compile: {compile_result.stderr}'
    )
    assert os.path.isfile(EXECUTABLE), 'Compilation did not produce an executable'

    # Preserve the original verifier's checks on the supplied fixtures.
    run_and_verify_case()

    # Re-run the compiled artifact on freshly generated values so a prewritten
    # report or hardcoded fixture answers cannot pass.
    install_dynamic_case()
    run_and_verify_case()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
