#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

PROJECT = Path('/home/user/forensics')
EVIDENCE = Path('/home/user/decrypted_evidence.txt')
SERVER_LOG = Path('/home/user/server.log')
ROOT_CA = Path('/home/user/rootCA.pem')
DATA_DIR = Path('/home/user/compromised_data')


def run_program(require_success=True):
    if EVIDENCE.exists() or EVIDENCE.is_symlink():
        EVIDENCE.unlink()
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=300,
    )
    if require_success:
        assert result.returncode == 0, (
            f'Rust program failed with exit code {result.returncode}.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
    return result


def openssl(*args):
    subprocess.run(
        ['openssl', *args],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def make_ca(work, prefix):
    key = work / f'{prefix}.key'
    cert = work / f'{prefix}.pem'
    openssl(
        'req', '-x509', '-sha256', '-nodes', '-days', '2',
        '-newkey', 'rsa:2048', '-subj', f'/CN={prefix}',
        '-keyout', str(key), '-out', str(cert),
    )
    return key, cert


def make_cert(work, prefix, cn, ca_key, ca_cert, destination):
    key = work / f'{prefix}.key'
    csr = work / f'{prefix}.csr'
    serial = work / f'{prefix}.srl'
    openssl(
        'req', '-new', '-newkey', 'rsa:2048', '-nodes',
        '-subj', f'/C=US/O=Verifier/CN={cn}',
        '-keyout', str(key), '-out', str(csr),
    )
    openssl(
        'x509', '-req', '-in', str(csr), '-CA', str(ca_cert),
        '-CAkey', str(ca_key), '-CAcreateserial', '-CAserial', str(serial),
        '-out', str(destination), '-days', '2', '-sha256',
    )


def write_payload(path, key, plaintext):
    nonce = secrets.token_bytes(12)
    path.write_bytes(nonce + AESGCM(key).encrypt(nonce, plaintext, None))


def write_log(cert_name, payload_name):
    SERVER_LOG.write_text(
        '192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET / HTTP/1.1" 200 2326\n'
        '10.0.0.5 - - [10/Oct/2023:13:55:40 -0700] "POST /upload?filename=legit.txt HTTP/1.1" 200 102\n'
        f'10.0.0.5 - - [10/Oct/2023:13:56:01 -0700] "POST /upload?filename=../../compromised_data/{cert_name} HTTP/1.1" 200 1024\n'
        f'10.0.0.5 - - [10/Oct/2023:13:56:05 -0700] "POST /upload?filename=../../compromised_data/{payload_name} HTTP/1.1" 200 512\n'
    )


def test_rust_project_exists_and_executes():
    assert PROJECT.is_dir(), 'Missing /home/user/forensics Rust project directory'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Missing Cargo.toml'
    assert any(p.is_file() for p in PROJECT.rglob('*.rs')), 'Rust project contains no .rs source files'
    run_program()


def test_decrypted_evidence_exists_and_correct():
    """Verify that the student successfully decrypted the payload and wrote the flag."""
    evidence_path = "/home/user/decrypted_evidence.txt"

    assert os.path.isfile(evidence_path), f"The final evidence file is missing: {evidence_path}"

    with open(evidence_path, "r") as f:
        content = f.read().strip()

    expected_flag = "FLAG{P4th_Tr4v3rs4l_C3rt_GCM_M4st3r}"
    assert content == expected_flag, (
        f"The decrypted payload does not match the expected flag.\n"
        f"Expected: {expected_flag}\n"
        f"Found: {content}"
    )


def test_randomized_log_parsing_validation_and_decryption():
    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        backup_log = work / 'server.log.backup'
        backup_ca = work / 'rootCA.pem.backup'
        backup_data = work / 'compromised_data.backup'
        backup_evidence = work / 'evidence.backup'
        shutil.copy2(SERVER_LOG, backup_log)
        shutil.copy2(ROOT_CA, backup_ca)
        shutil.copytree(DATA_DIR, backup_data)
        had_evidence = EVIDENCE.is_file()
        if had_evidence:
            shutil.copy2(EVIDENCE, backup_evidence)

        try:
            shutil.rmtree(DATA_DIR)
            DATA_DIR.mkdir()

            ca_key, ca_cert = make_ca(work, 'trusted-random-ca')
            shutil.copy2(ca_cert, ROOT_CA)

            token = secrets.token_hex(6)
            cert_name = f'beacon_{token}.pem'
            payload_name = f'archive_{token}.bin'
            key = secrets.token_bytes(32)
            plaintext = f'VERIFIED_DYNAMIC_{secrets.token_hex(18)}'.encode('ascii')
            make_cert(work, 'wanted', key.hex(), ca_key, ca_cert, DATA_DIR / cert_name)
            write_payload(DATA_DIR / payload_name, key, plaintext)

            # Valid decoys at the original hard-coded names ensure the uploaded paths
            # must be obtained from the traversal entries in server.log.
            decoy_key = secrets.token_bytes(32)
            decoy_plaintext = f'DECOY_{secrets.token_hex(18)}'.encode('ascii')
            make_cert(work, 'decoy', decoy_key.hex(), ca_key, ca_cert, DATA_DIR / 'c2_cert.pem')
            write_payload(DATA_DIR / 'payload.enc', decoy_key, decoy_plaintext)
            write_log(cert_name, payload_name)

            run_program()
            assert EVIDENCE.is_file(), 'Randomized run did not create decrypted_evidence.txt'
            assert EVIDENCE.read_bytes() == plaintext, (
                'Program did not select the uploaded files from server.log and decrypt '
                'the randomized AES-256-GCM payload'
            )

            # A certificate carrying a usable key but signed by another CA must not
            # be accepted merely because its payload decrypts successfully.
            shutil.rmtree(DATA_DIR)
            DATA_DIR.mkdir()
            rogue_key, rogue_ca = make_ca(work, 'rogue-random-ca')
            bad_cert_name = f'rogue_{secrets.token_hex(6)}.pem'
            bad_payload_name = f'rogue_{secrets.token_hex(6)}.enc'
            bad_aes_key = secrets.token_bytes(32)
            bad_plaintext = f'UNTRUSTED_{secrets.token_hex(18)}'.encode('ascii')
            make_cert(
                work, 'rogue-leaf', bad_aes_key.hex(), rogue_key, rogue_ca,
                DATA_DIR / bad_cert_name,
            )
            write_payload(DATA_DIR / bad_payload_name, bad_aes_key, bad_plaintext)
            write_log(bad_cert_name, bad_payload_name)

            run_program(require_success=False)
            produced = EVIDENCE.read_bytes() if EVIDENCE.is_file() else None
            assert produced != bad_plaintext, (
                'Program decrypted a payload whose certificate was not signed by rootCA.pem'
            )
        finally:
            shutil.copy2(backup_log, SERVER_LOG)
            shutil.copy2(backup_ca, ROOT_CA)
            if DATA_DIR.exists():
                shutil.rmtree(DATA_DIR)
            shutil.copytree(backup_data, DATA_DIR)
            if EVIDENCE.exists() or EVIDENCE.is_symlink():
                EVIDENCE.unlink()
            if had_evidence:
                shutil.copy2(backup_evidence, EVIDENCE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
