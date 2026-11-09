#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import subprocess

ANALYZE = '/home/user/analyze.sh'
ACCESS_LOG = '/app/access.log'
IPS_FILE = '/home/user/malicious_ips.txt'
FLAG_FILE = '/home/user/flag.txt'
AUDIT_LOG = '/var/log/recovery_access.log'

EXPECTED_TOKEN = (
    'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.'
    'eyJ1c2VyIjoiYWRtaW4iLCJyb2xlIjoic3VwZXJ1c2VyIn0.'
)
EXPECTED_FLAG = 'FLAG{jwt_alg_none_bypassed_successfully}'


def test_01_original_malicious_ips_f1_score():
    assert os.path.exists(IPS_FILE), f'File not found: {IPS_FILE}'

    with open(IPS_FILE, 'r') as f:
        predicted_ips = set(line.strip() for line in f if line.strip())

    ground_truth_ips = {
        '192.168.1.105', '10.0.0.42', '172.16.5.99', '198.51.100.23',
        '203.0.113.8', '192.0.2.55', '10.1.1.14', '172.18.9.200',
        '198.51.100.77', '203.0.113.101', '192.168.2.33', '10.0.5.5',
        '172.20.0.12', '198.51.100.150', '203.0.113.210'
    }

    true_positives = len(predicted_ips.intersection(ground_truth_ips))
    false_positives = len(predicted_ips - ground_truth_ips)
    false_negatives = len(ground_truth_ips - predicted_ips)

    if true_positives == 0:
        f1 = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.95, f'F1 score {f1:.4f} is below the required threshold of 0.95'


def test_02_analyze_script_parses_fresh_log():
    assert os.path.isfile(ANALYZE), f'File not found: {ANALYZE}'

    original_log = open(ACCESS_LOG, 'rb').read()
    nonce = secrets.token_bytes(12)
    octets = [int(x) for x in nonce]
    ips = [f'10.{octets[i]}.{octets[i+1]}.{20+i}' for i in range(0, 10, 2)]
    malicious = ips[:3]
    xss_only = ips[3]
    token_only = ips[4]

    header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').decode().rstrip('=')
    payload = base64.urlsafe_b64encode(b'{"user":"admin"}').decode().rstrip('=')
    none_token = f'{header}.{payload}.'

    lines = []
    payloads = ['%3Cscript%3Ealert(1)%3C/script%3E', 'javascript%3Aalert(1)', 'x%22%20onerror%3Dalert(1)']
    for ip, xss in zip(malicious, payloads):
        lines.append(f'{ip} - - [11/Sep/2026:10:00:00 +0000] "GET /?q={xss} HTTP/1.1" 200 -')
        lines.append(f'{ip} - - [11/Sep/2026:10:00:01 +0000] "GET /api HTTP/1.1" 200 - "Authorization: Bearer {none_token}"')
    lines.append(f'{xss_only} - - [11/Sep/2026:10:00:02 +0000] "GET /?q=%3Cscript%3E HTTP/1.1" 200 -')
    lines.append(f'{token_only} - - [11/Sep/2026:10:00:03 +0000] "GET /api HTTP/1.1" 200 - "Authorization: Bearer {none_token}"')
    lines.append(f'192.0.2.199 - - [11/Sep/2026:10:00:04 +0000] "GET /index.html HTTP/1.1" 200 -')

    try:
        with open(ACCESS_LOG, 'w') as f:
            f.write('\n'.join(lines) + '\n')
        if os.path.exists(IPS_FILE):
            os.unlink(IPS_FILE)
        result = subprocess.run(['/bin/bash', ANALYZE], text=True, capture_output=True, timeout=15)
        assert result.returncode == 0, f'analyze.sh failed: {result.stderr}'
        assert os.path.isfile(IPS_FILE), 'analyze.sh did not create malicious_ips.txt'
        with open(IPS_FILE) as f:
            actual = [line.strip() for line in f if line.strip()]
        expected = sorted(set(malicious), key=lambda ip: tuple(map(int, ip.split('.'))))
        lexical_expected = sorted(set(malicious))
        assert actual in (expected, lexical_expected), f'Fresh-log result was {actual}, expected {malicious}'
        assert len(actual) == len(set(actual)), 'Output contains duplicate IP addresses'
    finally:
        with open(ACCESS_LOG, 'wb') as f:
            f.write(original_log)


def test_03_certificate_chain_is_valid():
    result = subprocess.run([
        'openssl', 'verify', '-CAfile', '/app/certs/ca.crt',
        '-untrusted', '/app/certs/intermediate.crt', '/app/certs/server.crt'
    ], text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, result.stdout + result.stderr


def test_04_flag_file_contents():
    assert os.path.exists(FLAG_FILE), f'Flag file not found: {FLAG_FILE}'
    with open(FLAG_FILE, 'r') as f:
        flag_content = f.read().strip()
    assert EXPECTED_FLAG in flag_content, 'The flag file does not contain the expected secret evidence string.'


def test_05_recovery_service_was_contacted_with_required_jwt():
    assert os.path.isfile(AUDIT_LOG), 'Recovery service audit log is missing'
    with open(AUDIT_LOG, 'r') as f:
        records = f.read().splitlines()
    assert any(
        line.startswith('SUCCESS\t') and EXPECTED_TOKEN in line and '\tcurl/' in line
        for line in records
    ), 'No successful curl request using the required unsigned admin/superuser JWT was recorded'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
