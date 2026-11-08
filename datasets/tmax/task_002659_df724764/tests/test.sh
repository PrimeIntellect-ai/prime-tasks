#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import pytest


def base64url_decode(input_str):
    rem = len(input_str) % 4
    if rem > 0:
        input_str += '=' * (4 - rem)
    return base64.urlsafe_b64decode(input_str)


def trusted_verify_token(jwt_token, public_key):
    try:
        parts = jwt_token.split('.')
        if len(parts) != 3:
            return False

        header_b64, payload_b64, signature_b64 = parts
        header = json.loads(base64url_decode(header_b64).decode('utf-8'))
        payload = json.loads(base64url_decode(payload_b64).decode('utf-8'))

        if header.get('alg', '').lower() == 'none':
            pass
        else:
            # The supplied module's signature verifier always returns False.
            return False

        return payload.get('user') == 'admin'
    except Exception:
        return False


def decode_json_segment(segment):
    def reject_duplicate_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate JSON key')
            result[key] = value
        return result

    decoded = base64url_decode(segment).decode('utf-8')
    return json.loads(decoded, object_pairs_hook=reject_duplicate_keys)


def test_passphrase_cracked():
    passphrase_file = '/home/user/passphrase.txt'
    assert os.path.isfile(passphrase_file), f'{passphrase_file} does not exist.'

    with open(passphrase_file, 'r') as f:
        passphrase = f.read().strip()

    assert passphrase == 'secret123', 'The cracked passphrase in passphrase.txt is incorrect.'


def test_admin_token_forged():
    token_file = '/home/user/admin_token.txt'
    assert os.path.isfile(token_file), f'{token_file} does not exist.'

    with open(token_file, 'r') as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) == 3, 'The forged token does not have the correct JWT format (header.payload.signature).'

    header = decode_json_segment(parts[0])
    payload = decode_json_segment(parts[1])

    assert isinstance(header, dict), 'The JWT header must be a JSON object.'
    assert isinstance(header.get('alg'), str) and header['alg'].lower() == 'none', \
        "The token does not exploit the vulnerable 'none' algorithm bypass."
    assert type(payload) is dict and payload == {'user': 'admin'}, \
        "The JWT payload must be exactly {'user': 'admin'} with no additional claims."

    is_valid = trusted_verify_token(token, 'dummy_key')
    assert is_valid is True, 'The forged token failed verification or did not grant admin access.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
