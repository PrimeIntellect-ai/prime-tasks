#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

SOURCE = Path('/home/user/decryptor.c')
INDICATOR = Path('/home/user/c2_indicator.txt')
INCIDENT = Path('/home/user/incident')
CERT_DIR = INCIDENT / 'certs'


def test_c2_indicator_exists():
    """Verify that the C2 indicator file was created."""
    assert os.path.isfile('/home/user/c2_indicator.txt'), 'The file /home/user/c2_indicator.txt is missing.'


def test_c2_indicator_content():
    """Verify that the extracted IP address is correct."""
    assert os.path.isfile('/home/user/c2_indicator.txt'), 'Cannot check content because /home/user/c2_indicator.txt is missing.'
    with open('/home/user/c2_indicator.txt', 'r') as f:
        content = f.read().strip()

    expected_ip = '198.51.100.42'
    assert content == expected_ip, f"The content of /home/user/c2_indicator.txt is incorrect. Expected '{expected_ip}', found '{content}'."


def test_decryptor_c_exists():
    """Verify that the decryptor C source code file exists."""
    assert os.path.isfile('/home/user/decryptor.c'), 'The file /home/user/decryptor.c is missing. You must write your solution in this file.'


def run_program(executable, cwd):
    try:
        return subprocess.run(
            [str(executable)], cwd=cwd, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10, check=False
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError('The compiled decryptor did not terminate within 10 seconds') from exc


def valid_output(result):
    return 'CERT_CHAIN_VALID' in result.stdout.decode('utf-8', errors='replace').splitlines()


def test_compiled_decryptor_behaviour():
    assert SOURCE.is_file(), 'The file /home/user/decryptor.c is missing.'
    assert SOURCE.stat().st_size > 0, '/home/user/decryptor.c is empty.'

    with tempfile.TemporaryDirectory(prefix='decryptor-test-') as td:
        td = Path(td)
        executable = td / 'decryptor'
        build = subprocess.run(
            ['gcc', str(SOURCE), '-o', str(executable), '-lcrypto', '-lssl'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False
        )
        assert build.returncode == 0, 'decryptor.c does not compile with OpenSSL:\n' + build.stderr.decode('utf-8', errors='replace')
        assert executable.is_file() and os.access(executable, os.X_OK), 'Compilation did not produce an executable.'

        symbols = subprocess.run(
            ['nm', '-D', str(executable)], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10, check=True
        ).stdout.decode('utf-8', errors='replace')
        assert ('X509_verify_cert' in symbols or 'X509_verify' in symbols), 'The executable does not use OpenSSL certificate verification APIs.'
        assert (('EVP_Decrypt' in symbols or 'EVP_Cipher' in symbols) and 'EVP_aes_128_cbc' in symbols) or ('AES_cbc_encrypt' in symbols and 'AES_set_decrypt_key' in symbols), 'The executable does not use OpenSSL AES-CBC decryption APIs.'
        forbidden = re.compile(r'\b(system|popen|execl|execle|execlp|execv|execve|execvp|fork|vfork|posix_spawn)(?:@|$)', re.MULTILINE)
        assert not forbidden.search(symbols), 'The decryptor invokes external commands instead of performing validation/decryption in C.'

        payload_path = INCIDENT / 'payload.enc'
        cert_paths = [CERT_DIR / 'ca.crt', CERT_DIR / 'intermediate.crt', CERT_DIR / 'leaf.crt']
        original_payload = payload_path.read_bytes()
        original_certs = {p: p.read_bytes() for p in cert_paths}

        # First execute against the supplied artifacts. Try the two natural working
        # directories so relative-path implementations are not rejected arbitrarily.
        chosen_cwd = None
        failures = []
        for cwd in ('/home/user', '/home/user/incident'):
            INDICATOR.unlink(missing_ok=True)
            result = run_program(executable, cwd)
            produced = INDICATOR.read_bytes() if INDICATOR.exists() else b''
            if result.returncode == 0 and valid_output(result) and produced == b'198.51.100.42\n':
                chosen_cwd = cwd
                break
            failures.append((cwd, result.returncode, result.stdout, result.stderr, produced))
        assert chosen_cwd is not None, 'The compiled decryptor failed to validate and decrypt the supplied artifacts: ' + repr(failures)

        try:
            # Use a verifier-generated plaintext so a hardcoded indicator cannot pass.
            expected_ip = f'203.0.113.{secrets.randbelow(250) + 1}'
            plaintext = td / 'plaintext'
            encrypted = td / 'payload.enc'
            plaintext.write_bytes(('C2_SERVER=' + expected_ip).encode('ascii'))
            encrypt = subprocess.run([
                'openssl', 'enc', '-aes-128-cbc', '-in', str(plaintext),
                '-out', str(encrypted), '-K', '4d346c773472334b3379313233343536',
                '-iv', '0102030405060708090a0b0c0d0e0f10'
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False)
            assert encrypt.returncode == 0, 'Verifier could not prepare its randomized encrypted test payload.'
            payload_path.write_bytes(encrypted.read_bytes())

            INDICATOR.unlink(missing_ok=True)
            result = run_program(executable, chosen_cwd)
            assert result.returncode == 0, 'The decryptor failed on a valid randomized payload: ' + result.stderr.decode('utf-8', errors='replace')
            assert valid_output(result), 'The decryptor did not print CERT_CHAIN_VALID for the valid chain.'
            assert INDICATOR.is_file(), 'The decryptor did not create c2_indicator.txt.'
            assert INDICATOR.read_bytes() == expected_ip.encode('ascii') + b'\n', 'The decryptor did not decrypt and extract the verifier-generated C2 address exactly.'

            # Generate an unrelated certificate, then independently break every
            # position in the supplied chain. Decryption must not occur in any case.
            rogue_key = td / 'rogue.key'
            rogue_cert = td / 'rogue.crt'
            rogue = subprocess.run([
                'openssl', 'req', '-new', '-x509', '-nodes', '-days', '2',
                '-newkey', 'rsa:2048', '-keyout', str(rogue_key),
                '-out', str(rogue_cert), '-subj', '/CN=Untrusted Verifier Certificate'
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False)
            assert rogue.returncode == 0, 'Verifier could not generate its negative-test certificate.'
            rogue_bytes = rogue_cert.read_bytes()

            for broken_path in cert_paths:
                for path, data in original_certs.items():
                    path.write_bytes(data)
                broken_path.write_bytes(rogue_bytes)
                INDICATOR.unlink(missing_ok=True)
                bad = run_program(executable, chosen_cwd)
                assert not valid_output(bad), f'The decryptor reported CERT_CHAIN_VALID when {broken_path.name} was replaced by an untrusted certificate.'
                assert not INDICATOR.exists(), f'The decryptor created c2_indicator.txt despite an invalid {broken_path.name}.'
        finally:
            payload_path.write_bytes(original_payload)
            for path, data in original_certs.items():
                path.write_bytes(data)

        # Leave the required final artifact generated by the tested executable.
        INDICATOR.unlink(missing_ok=True)
        final_run = run_program(executable, chosen_cwd)
        assert final_run.returncode == 0 and valid_output(final_run), 'The decryptor failed after the original artifacts were restored.'
        assert INDICATOR.read_bytes() == b'198.51.100.42\n', 'The restored payload was not decrypted to the required final indicator.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
