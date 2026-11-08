#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import base64
import subprocess
import pytest

BASE_DIR = '/home/user/incident_014'
LOG_FILE = os.path.join(BASE_DIR, 'auth.log')
IPS_FILE = os.path.join(BASE_DIR, 'compromised_ips.txt')
FORGE_SCRIPT = os.path.join(BASE_DIR, 'forge.py')
TOKEN_FILE = os.path.join(BASE_DIR, 'forged_token.txt')

def decode_jwt_part(part: str) -> dict:
    padded = part + '===='
    decoded_bytes = base64.urlsafe_b64decode(padded)
    return json.loads(decoded_bytes.decode('utf-8'))

def test_compromised_ips_derived_from_log():
    assert os.path.isfile(LOG_FILE), f'Log file missing: {LOG_FILE}'

    expected_ips = set()
    with open(LOG_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split('] ', 1)[-1].split(' ')
            kv_pairs = {}
            for part in parts:
                if '=' in part:
                    k, v = part.split('=', 1)
                    kv_pairs[k] = v

            if kv_pairs.get('User') == 'admin' and kv_pairs.get('Status') == 'Success':
                token = kv_pairs.get('Token', '')
                token_parts = token.split('.')
                if len(token_parts) >= 1:
                    try:
                        header = decode_jwt_part(token_parts[0])
                        if header.get('alg', '').lower() == 'none':
                            expected_ips.add(kv_pairs.get('IP'))
                    except Exception:
                        pass

    expected_ips_sorted = sorted(list(expected_ips))

    assert os.path.isfile(IPS_FILE), f'Compromised IPs file missing: {IPS_FILE}'

    with open(IPS_FILE, 'r') as f:
        actual_ips = [line.strip() for line in f if line.strip()]

    assert actual_ips == expected_ips_sorted, (
        f'Contents of {IPS_FILE} do not match the expected exploited IPs.\n'
        f'Expected: {expected_ips_sorted}\n'
        f'Found: {actual_ips}'
    )

def test_forge_script_exists():
    assert os.path.isfile(FORGE_SCRIPT), f'Forge script missing: {FORGE_SCRIPT}'

def test_forged_token_validity():
    assert os.path.isfile(TOKEN_FILE), f'Forged token file missing: {TOKEN_FILE}'

    with open(TOKEN_FILE, 'r') as f:
        token = f.read().strip()

    assert token, f'The forged token file {TOKEN_FILE} is empty.'

    token_parts = token.split('.')
    assert len(token_parts) == 3, f'The token in {TOKEN_FILE} must have exactly 3 parts (header.payload.signature).'

    try:
        header = decode_jwt_part(token_parts[0])
    except Exception as e:
        pytest.fail(f'Failed to decode token header: {e}')

    try:
        payload = decode_jwt_part(token_parts[1])
    except Exception as e:
        pytest.fail(f'Failed to decode token payload: {e}')

    assert header.get('alg', '').lower() == 'none', (
        f"The forged token header must use the 'none' algorithm bypass. Found alg: {header.get('alg')}"
    )

    assert payload.get('user') == 'root', (
        f"The forged token payload must be for the user 'root'. Found user: {payload.get('user')}"
    )

def test_forge_script_generates_saved_token():
    assert os.path.isfile(FORGE_SCRIPT), f'Forge script missing: {FORGE_SCRIPT}'
    assert os.path.isfile(TOKEN_FILE), f'Forged token file missing: {TOKEN_FILE}'

    with open(TOKEN_FILE, 'rb') as f:
        saved_output = f.read()

    # The generator must work independently rather than merely reading the
    # already-created output file.
    os.unlink(TOKEN_FILE)
    try:
        result = subprocess.run(
            [sys.executable, FORGE_SCRIPT],
            cwd=BASE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
    finally:
        with open(TOKEN_FILE, 'wb') as f:
            f.write(saved_output)

    assert result.returncode == 0, (
        f'forge.py exited with status {result.returncode}. stderr: '
        f'{result.stderr.decode("utf-8", errors="replace")}'
    )
    assert result.stdout == saved_output, (
        'The exact stdout produced by forge.py does not match forged_token.txt.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
