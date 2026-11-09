#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import hmac
import hashlib
import datetime
import tempfile
from pathlib import Path

HOME = Path('/home/user')
OUTPUTS = [
    HOME / 'new_agent.key',
    HOME / 'new_agent.crt',
    HOME / 'auth.token',
    HOME / 'payload.bin',
    HOME / 'rotated_agent',
    HOME / 'rotation_summary.txt',
]

def run_cmd(cmd, input_data=None, timeout=30):
    return subprocess.run(
        cmd,
        input=input_data,
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout,
    )

def require_regular_file(path):
    assert path.exists(), f'{path} does not exist.'
    assert path.is_file() and not path.is_symlink(), f'{path} must be a regular file.'

def openssl_with_file(args, data):
    with tempfile.NamedTemporaryFile('wb', delete=False) as f:
        f.write(data)
        name = f.name
    try:
        return run_cmd(['openssl'] + args + [name])
    finally:
        os.unlink(name)

def test_complete_rotation():
    script = HOME / 'rotate_credentials.sh'
    require_regular_file(script)
    require_regular_file(HOME / 'base_agent')
    require_regular_file(HOME / 'master.key')

    base_hash_before = hashlib.sha256((HOME / 'base_agent').read_bytes()).digest()

    # The demanded script must create every artifact itself; pre-existing artifacts
    # cannot satisfy the verifier.
    for path in OUTPUTS:
        if path.exists() or path.is_symlink():
            path.unlink()

    result = run_cmd(['bash', str(script)], timeout=60)
    assert result.returncode == 0, (
        f'rotate_credentials.sh failed with exit code {result.returncode}:\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    require_regular_file(script)
    assert hashlib.sha256((HOME / 'base_agent').read_bytes()).digest() == base_hash_before, \
        'rotate_credentials.sh modified base_agent.'

    for path in OUTPUTS:
        require_regular_file(path)

    agent_path = HOME / 'rotated_agent'
    assert os.access(agent_path, os.X_OK), '/home/user/rotated_agent is not executable.'

    # Confirm both files are ELF objects and that removing only .secret_auth from
    # each produces byte-identical binaries. This catches corruption or changes to
    # any other part of the supplied base binary.
    assert (HOME / 'base_agent').read_bytes()[:4] == b'\x7fELF', 'base_agent is not an ELF binary.'
    assert agent_path.read_bytes()[:4] == b'\x7fELF', 'rotated_agent is not an ELF binary.'
    with tempfile.TemporaryDirectory() as td:
        base_clean = Path(td) / 'base.clean'
        rotated_clean = Path(td) / 'rotated.clean'
        res = run_cmd(['objcopy', '--remove-section', '.secret_auth', str(HOME / 'base_agent'), str(base_clean)])
        assert res.returncode == 0, f'Failed to normalize base_agent: {res.stderr}'
        res = run_cmd(['objcopy', '--remove-section', '.secret_auth', str(agent_path), str(rotated_clean)])
        assert res.returncode == 0, f'Failed to normalize rotated_agent: {res.stderr}'
        assert base_clean.read_bytes() == rotated_clean.read_bytes(), \
            'rotated_agent differs from base_agent outside .secret_auth.'

    extracted_path = Path('/tmp/extracted_secret_auth.bin')
    if extracted_path.exists():
        extracted_path.unlink()
    res = run_cmd(['objcopy', '-O', 'binary', '-j', '.secret_auth', str(agent_path), str(extracted_path)])
    assert res.returncode == 0, f'Failed to extract .secret_auth section: {res.stderr}'
    assert extracted_path.exists(), 'Extracted section file not found.'
    payload_bytes = extracted_path.read_bytes()
    try:
        payload = payload_bytes.decode('ascii')
    except UnicodeDecodeError as exc:
        raise AssertionError(f'.secret_auth payload is not ASCII text: {exc}')

    lines = payload.strip().split('\n')
    assert len(lines) > 3, 'Payload does not contain enough lines for HMAC, Cert, and Key.'
    hmac_hex = lines[0].strip()

    cert_begin = '-----BEGIN CERTIFICATE-----'
    cert_end_marker = '-----END CERTIFICATE-----'
    cert_start = payload.find(cert_begin)
    cert_end = payload.find(cert_end_marker, cert_start)
    assert cert_start != -1 and cert_end != -1, 'Certificate not found in payload.'
    cert_end += len(cert_end_marker)

    key_begin = '-----BEGIN PRIVATE KEY-----'
    key_end_marker = '-----END PRIVATE KEY-----'
    key_start = payload.find(key_begin, cert_end)
    if key_start == -1:
        key_begin = '-----BEGIN RSA PRIVATE KEY-----'
        key_end_marker = '-----END RSA PRIVATE KEY-----'
        key_start = payload.find(key_begin, cert_end)
    assert key_start != -1, 'Private key not found in payload.'
    key_end = payload.find(key_end_marker, key_start)
    assert key_end != -1, 'Private key end marker not found in payload.'
    key_end += len(key_end_marker)

    cert_pem = payload[cert_start:cert_end].encode('ascii')
    key_pem = payload[key_start:key_end].encode('ascii')

    # Standalone files and the assembled payload must be the actual artifacts
    # embedded in the ELF, in the specified order and with no extra section data.
    cert_file = (HOME / 'new_agent.crt').read_bytes()
    key_file = (HOME / 'new_agent.key').read_bytes()
    token_text = (HOME / 'auth.token').read_text(encoding='ascii').strip()
    expected_payload = token_text.encode('ascii') + b'\n' + cert_file + key_file
    assert (HOME / 'payload.bin').read_bytes() == expected_payload, 'payload.bin has incorrect contents or formatting.'
    assert payload_bytes == expected_payload, '.secret_auth does not exactly match payload.bin.'
    assert cert_file.strip() == cert_pem, 'Embedded certificate does not match new_agent.crt.'
    assert key_file.strip() == key_pem, 'Embedded private key does not match new_agent.key.'

    # Parse and validate the private key rather than trusting PEM marker text.
    key_check = openssl_with_file(['pkey', '-check', '-noout', '-in'], key_file)
    assert key_check.returncode == 0, f'Failed to parse or validate private key: {key_check.stderr}'
    key_text = openssl_with_file(['pkey', '-text', '-noout', '-in'], key_file)
    assert key_text.returncode == 0, f'Failed to inspect private key: {key_text.stderr}'
    assert '2048 bit' in key_text.stdout, 'Private key is not 2048-bit RSA.'

    # Verify the certificate subject strictly.
    subject = openssl_with_file(['x509', '-noout', '-subject', '-nameopt', 'RFC2253', '-in'], cert_file)
    assert subject.returncode == 0, 'Failed to parse certificate.'
    assert subject.stdout.strip() == 'subject=CN=auth-agent', f'Certificate subject is incorrect: {subject.stdout}'

    cert_text = openssl_with_file(['x509', '-noout', '-text', '-in'], cert_file)
    assert cert_text.returncode == 0, f'Failed to inspect certificate: {cert_text.stderr}'
    assert '2048 bit' in cert_text.stdout, 'Certificate is not 2048-bit RSA.'
    assert 'Public Key Algorithm: rsaEncryption' in cert_text.stdout, 'Certificate public key is not RSA.'

    # The key's public key must exactly match the certificate public key.
    key_pub = openssl_with_file(['pkey', '-pubout', '-outform', 'DER', '-in'], key_file)
    cert_pub = openssl_with_file(['x509', '-pubkey', '-noout', '-in'], cert_file)
    assert key_pub.returncode == 0 and cert_pub.returncode == 0, 'Failed to extract public keys.'
    cert_pub_der = run_cmd(['openssl', 'pkey', '-pubin', '-outform', 'DER'], input_data=cert_pub.stdout)
    assert cert_pub_der.returncode == 0, f'Failed to decode certificate public key: {cert_pub_der.stderr}'
    assert key_pub.stdout.encode('latin1') == cert_pub_der.stdout.encode('latin1'), \
        'Private key does not match the certificate.'

    # Check the exact 30-day lifetime and that the freshly generated certificate
    # is currently valid.
    dates = openssl_with_file(['x509', '-noout', '-startdate', '-enddate', '-in'], cert_file)
    assert dates.returncode == 0, f'Failed to inspect certificate dates: {dates.stderr}'
    date_values = dict(line.split('=', 1) for line in dates.stdout.strip().splitlines())
    fmt = '%b %d %H:%M:%S %Y %Z'
    not_before = datetime.datetime.strptime(date_values['notBefore'], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(date_values['notAfter'], fmt).replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=30), 'Certificate is not valid for exactly 30 days.'
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, 'Certificate is not currently valid.'
    assert now - not_before < datetime.timedelta(minutes=5), 'Certificate was not freshly generated by the script.'

    # Verify the certificate's self-signature, including the root signature.
    with tempfile.NamedTemporaryFile('wb', delete=False) as f:
        f.write(cert_file)
        cert_name = f.name
    try:
        verify = run_cmd(['openssl', 'verify', '-check_ss_sig', '-CAfile', cert_name, cert_name])
    finally:
        os.unlink(cert_name)
    assert verify.returncode == 0, f'Certificate is not validly self-signed: {verify.stderr}'

    fingerprint_result = openssl_with_file(['x509', '-noout', '-fingerprint', '-sha256', '-in'], cert_file)
    assert fingerprint_result.returncode == 0, 'Failed to get certificate fingerprint.'
    fingerprint_line = fingerprint_result.stdout.strip()
    assert 'Fingerprint=' in fingerprint_line, 'Unexpected fingerprint output format.'
    fingerprint = fingerprint_line.split('Fingerprint=', 1)[1].strip()

    master_key = (HOME / 'master.key').read_bytes()
    expected_hmac = hmac.new(master_key, fingerprint.encode('utf-8'), hashlib.sha256).hexdigest()
    assert hmac_hex == expected_hmac, f'HMAC in payload ({hmac_hex}) does not match expected HMAC ({expected_hmac}).'
    assert token_text == expected_hmac, 'auth.token does not contain the expected HMAC.'
    assert len(token_text) == 64 and all(c in '0123456789abcdef' for c in token_text), \
        'auth.token must be a lowercase hex-encoded SHA256 HMAC.'

    summary = (HOME / 'rotation_summary.txt').read_text(encoding='utf-8').strip().split('\n')
    assert len(summary) == 2, 'rotation_summary.txt must contain exactly two lines.'
    assert summary[0] == f'FINGERPRINT={fingerprint}', \
        f'rotation_summary.txt FINGERPRINT line incorrect. Expected FINGERPRINT={fingerprint}'
    assert summary[1] == f'TOKEN={expected_hmac}', \
        f'rotation_summary.txt TOKEN line incorrect. Expected TOKEN={expected_hmac}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
