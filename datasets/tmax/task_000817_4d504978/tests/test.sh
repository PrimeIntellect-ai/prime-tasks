#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import os
import socket
import stat

import pandas as pd
import pytest

SECRET = b'my_super_secret_key'
TARGETS_PATH = '/home/user/targets.txt'
PRED_PATH = '/home/user/audit_results.csv'


def receive_token(port):
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
            sock.settimeout(3)
            data = b''
            while b'\n' not in data and len(data) < 4096:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                data += chunk
    except OSError as exc:
        pytest.fail(f'Could not connect to simulated service on port {port}: {exc}')
    return data.split(b'\n', 1)[0].decode('utf-8', errors='strict').rstrip('\r')


def token_is_valid(token):
    if ':' not in token:
        return False
    data, supplied_mac = token.split(':', 1)
    expected_mac = hmac.new(SECRET, data.encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(supplied_mac, expected_mac)


def derive_truth():
    assert os.path.isfile(TARGETS_PATH), f'Target list {TARGETS_PATH} is missing.'
    rows = []
    with open(TARGETS_PATH, encoding='utf-8') as targets:
        for line in targets:
            line = line.strip()
            if not line:
                continue
            port_text, config_path, expected_sha = line.split(',', 2)
            port = int(port_text)
            with open(config_path, 'rb') as config_file:
                actual_sha = hashlib.sha256(config_file.read()).hexdigest()

            if actual_sha != expected_sha.strip().lower():
                status = 'TAMPERED'
            elif os.stat(config_path).st_mode & stat.S_IWOTH:
                status = 'VULNERABLE_PERMS'
            else:
                token = receive_token(port)
                status = 'SECURE' if token_is_valid(token) else 'VULNERABLE_TOKEN'
            rows.append({'Port': port, 'Status': status})
    return pd.DataFrame(rows).set_index('Port')


def test_audit_results_accuracy():
    assert os.path.isfile(PRED_PATH), f'Output file {PRED_PATH} is missing. The auditing tool did not produce the expected output file.'

    try:
        pred = pd.read_csv(PRED_PATH).set_index('Port')
    except Exception as exc:
        pytest.fail(f'Failed to read {PRED_PATH} as a CSV: {exc}')

    truth = derive_truth()
    assert 'Status' in pred.columns, f"Expected column 'Status' not found in {PRED_PATH}."

    joined = truth.join(pred, lsuffix='_truth', rsuffix='_pred')
    accuracy = (joined['Status_truth'] == joined['Status_pred']).mean()
    assert accuracy >= 0.95, f'Accuracy {accuracy:.4f} is below the required threshold of 0.95.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
