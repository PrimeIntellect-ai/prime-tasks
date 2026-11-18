#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import re
import subprocess
import tempfile


def expected_from_binary():
    with open('/home/user/upload_auth.bin', 'rb') as f:
        data = f.read()
    marker = b'SALT:'
    pos = data.find(marker)
    assert pos >= 0, 'The SALT: marker is missing from upload_auth.bin.'
    salt_bytes = data[pos + len(marker):pos + len(marker) + 16]
    assert len(salt_bytes) == 16, 'Could not extract the 16-character salt.'
    salt = salt_bytes.decode('ascii')
    digest = hashlib.sha256(('StrictPassword2024!' + salt).encode('utf-8')).hexdigest()
    return 'AUTH-TOKEN-' + digest


def assert_elf(path):
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not an ELF executable.'


def assert_uses_openssl_sha(path):
    dynamic = subprocess.run(
        ['readelf', '-d', path], text=True, capture_output=True, check=True
    ).stdout
    assert re.search(r'NEEDED.*libcrypto', dynamic), (
        f'{path} is not dynamically linked against the OpenSSL crypto library.'
    )
    symbols = subprocess.run(
        ['nm', '-D', path], text=True, capture_output=True, check=True
    ).stdout
    assert re.search(r'\bSHA256(?:_Init|_Update|_Final)?(?:@|\b)', symbols), (
        f'{path} does not reference an OpenSSL SHA-256 function.'
    )


def run_as_user(path):
    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    subprocess.run(
        [path], cwd='/home/user', check=True, timeout=10,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        preexec_fn=demote,
    )


def assert_generated_token(path):
    token_path = '/home/user/new_token.txt'
    if os.path.lexists(token_path):
        os.unlink(token_path)
    run_as_user(path)
    assert os.path.isfile(token_path), f'{path} did not create {token_path}.'
    with open(token_path, 'r') as f:
        content = f.read()
    assert content == expected_from_binary(), (
        f'{path} generated an incorrect token or included extra whitespace.'
    )


def test_keygen_cpp_exists():
    path = '/home/user/keygen.cpp'
    assert os.path.isfile(path), f'File {path} does not exist. You need to write the C++ program.'


def test_keygen_executable_exists():
    path = '/home/user/keygen'
    assert os.path.isfile(path), f'Executable {path} does not exist. You need to compile the C++ program.'
    assert os.access(path, os.X_OK), f'File {path} is not executable.'


def test_new_token_correct():
    path = '/home/user/new_token.txt'
    assert os.path.isfile(path), f'File {path} does not exist. The program must generate it.'

    password = 'StrictPassword2024!'
    salt = '8xK#mP9vLq2$zR5w'
    combined = password + salt
    expected_hash = hashlib.sha256(combined.encode('utf-8')).hexdigest()
    expected_token = f'AUTH-TOKEN-{expected_hash}'

    with open(path, 'r') as f:
        content = f.read()

    assert content == expected_token, f"The contents of {path} are incorrect. Expected '{expected_token}', but got '{content}'."


def test_source_and_executable_perform_required_generation():
    source_path = '/home/user/keygen.cpp'
    executable_path = '/home/user/keygen'

    with open(source_path, 'r', errors='replace') as f:
        source = f.read()
    assert re.search(r'#\s*include\s*<\s*openssl/sha\.h\s*>', source), (
        'keygen.cpp must include <openssl/sha.h>.'
    )

    assert_elf(executable_path)
    assert_uses_openssl_sha(executable_path)
    assert_generated_token(executable_path)

    build_dir = tempfile.mkdtemp(prefix='keygen_verify_')
    rebuilt = os.path.join(build_dir, 'keygen')
    result = subprocess.run(
        ['g++', source_path, '-o', rebuilt, '-lcrypto'],
        text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        'keygen.cpp could not be compiled and linked with -lcrypto:\n'
        + result.stdout + result.stderr
    )
    assert_elf(rebuilt)
    assert_uses_openssl_sha(rebuilt)
    assert_generated_token(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
