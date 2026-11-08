#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import struct
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
ROOT = HOME / 'root_ca.pem'
SCRIPT = HOME / 'audit_verify.go'
RESULT = HOME / 'compliance_result.txt'
ELF = HOME / 'legacy_processor'
CHAIN = HOME / 'server_chain.pem'
AUDIT = HOME / 'audit_data.bin'
EXPECTED_ORIGINAL = 'STATUS: VALID - PAYLOAD: SECURE_AUDIT_998'


def run_script():
    return subprocess.run(
        ['go', 'run', str(SCRIPT)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )


def test_root_ca_extracted():
    """Verify that the root_ca.pem was extracted correctly."""
    root_ca_path = '/home/user/root_ca.pem'
    assert os.path.isfile(root_ca_path), f'Missing file: {root_ca_path}'

    with open(root_ca_path, 'r') as f:
        content = f.read()
    assert 'BEGIN CERTIFICATE' in content, f'File {root_ca_path} does not contain a valid PEM certificate.'

    with tempfile.TemporaryDirectory() as td:
        dumped = Path(td) / 'auth_root.bin'
        proc = subprocess.run(
            ['objcopy', f'--dump-section', f'.auth_root={dumped}', str(ELF)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert proc.returncode == 0, proc.stderr.decode(errors='replace')
        assert dumped.is_file(), 'The ELF does not contain an extractable .auth_root section'
        assert ROOT.read_bytes() == dumped.read_bytes(), 'root_ca.pem is not the raw .auth_root section contents'

    proc = subprocess.run(
        ['openssl', 'x509', '-in', str(ROOT), '-noout'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert proc.returncode == 0, 'root_ca.pem is not a parseable X.509 PEM certificate'


def test_go_script_exists():
    """Verify that the Go script was created."""
    go_script_path = '/home/user/audit_verify.go'
    assert os.path.isfile(go_script_path), f'Missing file: {go_script_path}'


def test_compliance_result():
    """Verify the final compliance result file exists and has the correct content."""
    result_path = '/home/user/compliance_result.txt'
    assert os.path.isfile(result_path), f'Missing file: {result_path}'

    with open(result_path, 'r') as f:
        content = f.read()

    expected_content = 'STATUS: VALID - PAYLOAD: SECURE_AUDIT_998'
    assert content == expected_content, f"Expected content '{expected_content}', but got '{content}'"


def test_script_execution_validation_and_binary_parsing():
    original_root = ROOT.read_bytes()
    original_chain = CHAIN.read_bytes()
    original_audit = AUDIT.read_bytes()

    certs = re.findall(
        rb'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\s*',
        original_chain,
        flags=re.DOTALL,
    )
    assert len(certs) == 2, 'server_chain.pem must contain a leaf and an intermediate certificate'

    try:
        # Independently confirm that the supplied leaf validates for the required
        # hostname through the supplied intermediate to the extracted root.
        with tempfile.TemporaryDirectory() as td:
            leaf = Path(td) / 'leaf.pem'
            intermediate = Path(td) / 'intermediate.pem'
            leaf.write_bytes(certs[0])
            intermediate.write_bytes(certs[1])
            proc = subprocess.run(
                ['openssl', 'verify', '-CAfile', str(ROOT), '-untrusted', str(intermediate),
                 '-verify_hostname', 'audit.internal', str(leaf)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            assert proc.returncode == 0, proc.stderr.decode(errors='replace')

        # Execute the submitted Go source against a verifier-selected payload so
        # a hardcoded copy of the known result cannot pass.
        payload = ('DYNAMIC_' + secrets.token_hex(12)).encode('ascii')
        audit = (
            struct.pack('<HH', 0x0001, 5) + b'noise' +
            struct.pack('<HH', 0x0077, len(payload)) + payload +
            struct.pack('<HH', 0x0077, 6) + b'second' +
            struct.pack('<HH', 0x0002, 2) + b'OK'
        )
        AUDIT.write_bytes(audit)
        RESULT.unlink(missing_ok=True)
        proc = run_script()
        assert proc.returncode == 0, proc.stderr.decode(errors='replace')
        assert RESULT.is_file(), 'The executed Go program did not create compliance_result.txt'
        expected = b'STATUS: VALID - PAYLOAD: ' + payload
        assert RESULT.read_bytes() == expected, 'The Go program did not parse the first 0x0077 record correctly'

        # Keep the correct extracted root, but replace the server chain with two
        # parseable certificates that cannot be a leaf for audit.internal. The
        # program must reject it and must not create a result.
        CHAIN.write_bytes(original_root + original_root)
        RESULT.unlink(missing_ok=True)
        proc = run_script()
        assert proc.returncode != 0, 'The Go program accepted an invalid server certificate chain'
        assert not RESULT.exists(), 'The Go program wrote a result after certificate validation failed'
    finally:
        ROOT.write_bytes(original_root)
        CHAIN.write_bytes(original_chain)
        AUDIT.write_bytes(original_audit)
        RESULT.unlink(missing_ok=True)

    # Re-run on the original inputs and retain the original final-state assertion.
    proc = run_script()
    assert proc.returncode == 0, proc.stderr.decode(errors='replace')
    assert RESULT.is_file(), 'The Go program did not create the result for the valid original inputs'
    assert RESULT.read_text() == EXPECTED_ORIGINAL
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
