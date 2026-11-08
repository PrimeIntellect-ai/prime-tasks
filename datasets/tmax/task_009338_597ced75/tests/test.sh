#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
cp -a /home/user/repo "$BACKUP_DIR/repo"
if [ -f /home/user/policy_report.json ]; then
    cp -a /home/user/policy_report.json "$BACKUP_DIR/policy_report.json"
fi
restore_state() {
    rm -rf /home/user/repo
    cp -a "$BACKUP_DIR/repo" /home/user/repo
    rm -f /home/user/policy_report.json
    if [ -f "$BACKUP_DIR/policy_report.json" ]; then
        cp -a "$BACKUP_DIR/policy_report.json" /home/user/policy_report.json
    fi
    rm -rf "$BACKUP_DIR"
}
trap restore_state EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import pytest

PROJECT = Path('/home/user/policy-scanner')
REPO = Path('/home/user/repo')
REPORT = Path('/home/user/policy_report.json')
PATTERN = re.compile(r"res\.redirect\(.*req\.query\.(return_to|next).*\)")


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, timeout=120, **kwargs)


def run_scanner():
    REPORT.unlink(missing_ok=True)
    run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert REPORT.is_file(), 'The compiled Rust scanner did not create /home/user/policy_report.json.'
    with REPORT.open() as f:
        report = json.load(f)
    expected_keys = {'open_redirect_found', 'cert_valid', 'integrity_valid'}
    assert set(report.keys()) == expected_keys
    assert all(type(report[key]) is bool for key in expected_keys)
    return report


def test_rust_project_builds_and_runs():
    assert PROJECT.is_dir(), '/home/user/policy-scanner does not exist.'
    manifest = PROJECT / 'Cargo.toml'
    assert manifest.is_file(), 'Cargo.toml does not exist.'
    rust_sources = list(PROJECT.rglob('*.rs'))
    assert rust_sources, 'The project contains no Rust source files.'
    assert any(path.read_text(errors='ignore').strip() for path in rust_sources), 'Rust source files are empty.'

    cargo_text = manifest.read_text(errors='ignore')
    source_text = '\n'.join(path.read_text(errors='ignore') for path in rust_sources)
    assert re.search(r'(?m)^\s*sha2\s*=', cargo_text), 'Cargo.toml must declare the sha2 crate.'
    assert 'sha2' in source_text and 'Sha256' in source_text, 'Rust code must compute SHA-256 using sha2.'

    run(
        ['cargo', 'build', '--manifest-path', str(manifest)],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    run_scanner()


def test_policy_report_exists():
    """Test that the policy_report.json file was created."""
    filepath = "/home/user/policy_report.json"
    assert os.path.isfile(filepath), f"File {filepath} does not exist. The Rust program must generate this file."


def test_policy_report_content():
    """Test that the policy_report.json contains the correct boolean results."""
    filepath = "/home/user/policy_report.json"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    try:
        with open(filepath, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {filepath} does not contain valid JSON.")

    expected_keys = {"open_redirect_found", "cert_valid", "integrity_valid"}
    assert set(report.keys()) == expected_keys, f"Report keys {set(report.keys())} do not match expected keys {expected_keys}."

    assert report["open_redirect_found"] is True, "Expected 'open_redirect_found' to be true."
    assert report["cert_valid"] is True, "Expected 'cert_valid' to be true."
    assert report["integrity_valid"] is False, "Expected 'integrity_valid' to be false."


def make_certificates(directory):
    directory = Path(directory)
    for name in ('ca1', 'ca2'):
        run([
            'openssl', 'req', '-x509', '-nodes', '-days', '2', '-newkey', 'rsa:2048',
            '-keyout', str(directory / f'{name}.key'),
            '-out', str(directory / f'{name}.crt'),
            '-subj', f'/CN=Verifier-{name}-{os.urandom(6).hex()}'
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run([
        'openssl', 'req', '-nodes', '-newkey', 'rsa:2048',
        '-keyout', str(directory / 'server.key'),
        '-out', str(directory / 'server.csr'),
        '-subj', f'/CN=scanner-test-{os.urandom(6).hex()}.local'
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run([
        'openssl', 'x509', '-req', '-in', str(directory / 'server.csr'),
        '-CA', str(directory / 'ca1.crt'), '-CAkey', str(directory / 'ca1.key'),
        '-CAcreateserial', '-out', str(directory / 'server.crt'), '-days', '2'
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def derive_expected():
    auth = (REPO / 'src/auth.js').read_text()
    open_redirect = PATTERN.search(auth) is not None

    cert_check = subprocess.run(
        ['openssl', 'verify', '-CAfile', str(REPO / 'certs/ca.crt'), str(REPO / 'certs/server.crt')],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
    )
    cert_valid = cert_check.returncode == 0

    deploy = (REPO / 'deploy.yaml').read_bytes()
    expected_hash = (REPO / 'deploy.yaml.sha256').read_text().split()[0].lower()
    integrity_valid = hashlib.sha256(deploy).hexdigest() == expected_hash
    return {
        'open_redirect_found': open_redirect,
        'cert_valid': cert_valid,
        'integrity_valid': integrity_valid,
    }


def configure_case(cert_dir, vulnerable, valid_cert, valid_integrity):
    token = os.urandom(12).hex()
    if vulnerable:
        auth = f"app.get('/{token}', (req, res) => {{ res.redirect(req.query.next || '/home'); }});\n"
    else:
        auth = f"app.get('/{token}', (req, res) => {{ res.redirect('/home'); }});\n"
    (REPO / 'src/auth.js').write_text(auth)

    shutil.copy2(Path(cert_dir) / 'server.crt', REPO / 'certs/server.crt')
    selected_ca = 'ca1.crt' if valid_cert else 'ca2.crt'
    shutil.copy2(Path(cert_dir) / selected_ca, REPO / 'certs/ca.crt')

    deploy = os.urandom(48) + token.encode()
    (REPO / 'deploy.yaml').write_bytes(deploy)
    actual_hash = hashlib.sha256(deploy).hexdigest()
    recorded_hash = actual_hash if valid_integrity else hashlib.sha256(deploy + b'tampered').hexdigest()
    (REPO / 'deploy.yaml.sha256').write_text(f'{recorded_hash}  deploy.yaml\n')


def test_scanner_reacts_to_independent_repository_changes():
    with tempfile.TemporaryDirectory() as cert_dir:
        make_certificates(cert_dir)
        cases = [
            (False, True, True),
            (True, False, True),
            (False, False, False),
            (True, True, False),
        ]
        for vulnerable, valid_cert, valid_integrity in cases:
            configure_case(cert_dir, vulnerable, valid_cert, valid_integrity)
            expected = derive_expected()
            assert expected == {
                'open_redirect_found': vulnerable,
                'cert_valid': valid_cert,
                'integrity_valid': valid_integrity,
            }, 'Verifier-generated test fixture did not have the intended properties.'
            assert run_scanner() == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
