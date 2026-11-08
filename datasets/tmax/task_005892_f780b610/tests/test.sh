#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import subprocess
import tempfile

CREDENTIALS_DIR = '/home/user/credentials'
SERVICE_KEY = os.path.join(CREDENTIALS_DIR, 'service_key')
SERVICE_KEY_PUB = os.path.join(CREDENTIALS_DIR, 'service_key.pub')
ENCODER_C = os.path.join(CREDENTIALS_DIR, 'encoder.c')
ENCODER_BIN = os.path.join(CREDENTIALS_DIR, 'encoder')
OBFUSCATED_PAYLOAD = os.path.join(CREDENTIALS_DIR, 'obfuscated_payload.txt')
PAYLOAD_CHECKSUM = os.path.join(CREDENTIALS_DIR, 'payload_checksum.txt')


def expected_encoding(data):
    return ''.join(f'{byte ^ 0x5C:02X}' for byte in data).encode('ascii')


def run_encoder(path, data):
    result = subprocess.run(
        [path],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert result.returncode == 0, (
        f'Encoder {path} exited with {result.returncode}: '
        f'{result.stderr.decode("utf-8", errors="replace")}'
    )
    assert result.stdout == expected_encoding(data), (
        f'Encoder {path} did not produce the required uppercase XOR hexadecimal output.'
    )


def test_credentials_dir_exists():
    assert os.path.isdir(CREDENTIALS_DIR), f'Directory {CREDENTIALS_DIR} does not exist.'


def test_ssh_key_exists_and_valid():
    assert os.path.isfile(SERVICE_KEY), f'Private key {SERVICE_KEY} does not exist.'
    assert os.path.isfile(SERVICE_KEY_PUB), f'Public key {SERVICE_KEY_PUB} does not exist.'

    result = subprocess.run(
        ['ssh-keygen', '-l', '-f', SERVICE_KEY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert result.returncode == 0, f'ssh-keygen validation failed for {SERVICE_KEY}:\n{result.stderr}'
    assert 'ED25519' in result.stdout.upper(), f'The key {SERVICE_KEY} does not appear to be an ed25519 key.'


def test_public_key_matches_private_key():
    derived = subprocess.run(
        ['ssh-keygen', '-y', '-f', SERVICE_KEY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert derived.returncode == 0, f'Could not derive public key from private key:\n{derived.stderr}'

    with open(SERVICE_KEY_PUB, 'r', encoding='utf-8') as f:
        public_fields = f.read().split()
    derived_fields = derived.stdout.split()

    assert len(public_fields) >= 2, 'service_key.pub is not a valid SSH public-key record.'
    assert len(derived_fields) >= 2, 'ssh-keygen returned an invalid derived public key.'
    assert public_fields[0] == 'ssh-ed25519', 'service_key.pub is not an ed25519 public key.'
    assert public_fields[:2] == derived_fields[:2], 'service_key.pub does not correspond to service_key.'


def test_encoder_files_exist():
    assert os.path.isfile(ENCODER_C), f'Source file {ENCODER_C} does not exist.'
    assert os.path.isfile(ENCODER_BIN), f'Executable {ENCODER_BIN} does not exist.'
    assert os.access(ENCODER_BIN, os.X_OK), f'File {ENCODER_BIN} is not executable.'


def test_installed_encoder_behavior():
    cases = [
        b'',
        b'A',
        b'legacy pipeline\nwith binary:\x00\xff',
        bytes(range(256)),
        os.urandom(193),
    ]
    for data in cases:
        run_encoder(ENCODER_BIN, data)


def test_encoder_source_compiles_and_implements_encoding():
    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt_encoder = os.path.join(temp_dir, 'encoder')
        result = subprocess.run(
            ['gcc', '-std=c11', '-Wall', '-Wextra', '-pedantic', ENCODER_C, '-o', rebuilt_encoder],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        assert result.returncode == 0, f'encoder.c does not compile with gcc:\n{result.stderr}'

        cases = [
            b'',
            b'A',
            b'input with trailing newline\n',
            bytes(range(256)),
            os.urandom(257),
        ]
        for data in cases:
            run_encoder(rebuilt_encoder, data)


def test_obfuscated_payload():
    assert os.path.isfile(OBFUSCATED_PAYLOAD), f'Payload file {OBFUSCATED_PAYLOAD} does not exist.'

    with open(SERVICE_KEY_PUB, 'rb') as f:
        pub_key = f.read()

    expected_obfuscated = ''.join([f'{b ^ 0x5C:02X}' for b in pub_key]).encode('utf-8')

    with open(OBFUSCATED_PAYLOAD, 'rb') as f:
        actual_obfuscated = f.read()

    assert expected_obfuscated == actual_obfuscated, 'Obfuscated payload does not match expected XOR hex output.'

    result = subprocess.run(
        [ENCODER_BIN],
        input=pub_key,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert result.returncode == 0, 'The installed encoder failed when processing service_key.pub.'
    assert result.stdout == actual_obfuscated, 'obfuscated_payload.txt was not reproduced by the installed encoder.'


def test_payload_checksum():
    assert os.path.isfile(PAYLOAD_CHECKSUM), f'Checksum file {PAYLOAD_CHECKSUM} does not exist.'

    with open(OBFUSCATED_PAYLOAD, 'rb') as f:
        payload_data = f.read()

    expected_hash = hashlib.sha256(payload_data).hexdigest()

    with open(PAYLOAD_CHECKSUM, 'r') as f:
        actual_hash = f.read().strip()

    assert expected_hash == actual_hash, 'Checksum does not match the sha256 of the obfuscated payload.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
