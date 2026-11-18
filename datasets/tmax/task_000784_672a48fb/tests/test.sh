#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import re
import subprocess
import uuid
from pathlib import Path

from cryptography import x509
from cryptography.fernet import Fernet
from cryptography.x509.oid import NameOID

HOME = Path('/home/user')
OUTPUT = HOME / 'clean_audit.json'
INPUT_PATHS = [HOME / 'audit_logs.enc', HOME / 'secret.key', HOME / 'server.crt']
CARD_RE = re.compile(r'(?:\d{4}-\d{4}-\d{4}-\d{4}|\d{16})')


def expected_from_inputs():
    key = (HOME / 'secret.key').read_bytes().strip()
    token = (HOME / 'audit_logs.enc').read_bytes().strip()
    source = json.loads(Fernet(key).decrypt(token).decode('utf-8'))
    cert = x509.load_pem_x509_certificate((HOME / 'server.crt').read_bytes())
    issuer = cert.issuer.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value

    expected = copy.deepcopy(source)
    for log in expected:
        log['message'] = CARD_RE.sub('[REDACTED]', log['message'])
        log['cert_issuer'] = issuer
    return expected


def read_and_validate(expected):
    assert OUTPUT.exists(), f'File {OUTPUT} does not exist.'
    assert OUTPUT.is_file(), f'{OUTPUT} is not a file.'
    content = OUTPUT.read_text(encoding='utf-8')
    try:
        actual = json.loads(content)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {OUTPUT} does not contain valid JSON: {exc}')

    assert isinstance(actual, list), 'The JSON root should be a list of dictionaries.'
    assert actual == expected, 'The cleaned audit does not exactly match the decrypted, redacted, and enriched input.'
    canonical = json.dumps(actual, indent=2)
    assert content.strip() == canonical, 'The JSON file is not pretty-printed with a 2-space indent.'
    return actual


def run_script(script):
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    result = subprocess.run(
        ['python3', str(script)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{script} failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def test_script_processes_original_and_unseen_inputs():
    backups = {path: path.read_bytes() for path in INPUT_PATHS}
    candidates = sorted(
        (p for p in HOME.rglob('*.py') if p.is_file() and '__pycache__' not in p.parts),
        key=lambda p: (p.name != 'process_audit.py', str(p)),
    )
    assert candidates, 'No Python processing script was found under /home/user.'

    selected = None
    original_actual = None
    errors = []
    try:
        # Execute candidate scripts against the supplied files. A pre-created JSON
        # file cannot pass because it is removed before every execution.
        for script in candidates:
            for path, data in backups.items():
                path.write_bytes(data)
            try:
                expected = expected_from_inputs()
                run_script(script)
                original_actual = read_and_validate(expected)
                selected = script
                break
            except Exception as exc:
                errors.append(f'{script}: {exc}')

        assert selected is not None, 'No submitted Python script generated the required output. ' + ' | '.join(errors)

        # Retain the original verifier's concrete assertions.
        assert len(original_actual) == 4, f'Expected 4 logs, found {len(original_actual)}.'
        assert original_actual[1].get('message') == 'Payment processed for card [REDACTED] successfully.'
        assert original_actual[3].get('message') == 'Direct billing account updated for [REDACTED].'
        for i, log in enumerate(original_actual):
            assert log.get('cert_issuer') == 'ComplianceCA', f'Log at index {i} has incorrect cert_issuer.'

        # Replace all inputs with an unpredictable audit and certificate, then
        # execute the same script again to ensure it actually reads and processes them.
        nonce = uuid.uuid4().hex
        issuer = 'AuditCA-' + nonce[:12]
        trial_logs = [
            {'id': 'X-' + nonce[:8], 'timestamp': nonce[8:20], 'message': 'Ordinary event ' + nonce},
            {'id': 'Y-' + nonce[4:12], 'timestamp': nonce[12:24], 'message': 'Card 4321-8765-2109-6543 accepted.'},
            {'id': 'Z-' + nonce[8:16], 'timestamp': nonce[16:28], 'message': 'Account 1111222233334444 updated.', 'extra': nonce},
            {'id': 'W-' + nonce[12:20], 'timestamp': nonce[20:32], 'message': 'No payment data here.', 'cert_issuer': 'wrong'},
            {'id': 'V-' + nonce[16:24], 'timestamp': nonce[:12], 'message': 'Two cards 9999-8888-7777-6666 and 5555444433332222.'},
        ]
        key = Fernet.generate_key()
        (HOME / 'secret.key').write_bytes(key)
        (HOME / 'audit_logs.enc').write_bytes(Fernet(key).encrypt(json.dumps(trial_logs).encode('utf-8')))
        subprocess.run(
            ['openssl', 'req', '-x509', '-newkey', 'rsa:2048',
             '-keyout', '/tmp/verifier-audit.key', '-out', str(HOME / 'server.crt'),
             '-days', '1', '-nodes', '-subj', f'/CN={issuer}'],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30,
        )

        expected_trial = expected_from_inputs()
        run_script(selected)
        read_and_validate(expected_trial)
    finally:
        for path, data in backups.items():
            path.write_bytes(data)
        # Leave the requested output corresponding to the original supplied inputs.
        if selected is not None:
            try:
                run_script(selected)
            except Exception:
                pass

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
