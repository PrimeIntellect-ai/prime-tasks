#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import string
import subprocess
from pathlib import Path

HOME = Path('/home/user')
WORDLIST_PATH = HOME / 'wordlist.txt'
ADMIN_TOKEN_PATH = HOME / 'admin_token.txt'
FORGED_TOKEN_PATH = HOME / 'forged_token.txt'
HEADER_PATH = HOME / 'custom_crypto.h'

EXPECTED_PASSWORDS = [
    'password123',
    'admin123',
    'hunter2',
    'sunshine',
    'p@ssw0rd2023',
    'qwerty',
    'letmein1',
]
EXPECTED_WORDLIST = ''.join(p + '\n' for p in EXPECTED_PASSWORDS)
EXPECTED_HEADER = '''#ifndef CUSTOM_CRYPTO_H
#define CUSTOM_CRYPTO_H

#include <string>
#include <iomanip>
#include <sstream>

// Custom FNV-1a based weak hashing
inline std::string custom_hash(const std::string& input) {
    unsigned int hash = 0x811c9dc5;
    for (char c : input) {
        hash ^= static_cast<unsigned char>(c);
        hash *= 0x01000193;
    }
    std::stringstream ss;
    ss << std::hex << std::setw(8) << std::setfill('0') << hash;
    return ss.str();
}

inline std::string generate_token(const std::string& username, const std::string& password) {
    // Format: username||password||STATIC_SALT
    std::string data = username + "||" + password + "||SECURE_SALT_99";
    return custom_hash(data);
}

#endif // CUSTOM_CRYPTO_H
'''


def fnv1a(text):
    h = 0x811c9dc5
    for c in text:
        h ^= ord(c)
        h = (h * 0x01000193) & 0xFFFFFFFF
    return f'{h:08x}'


EXPECTED_ADMIN_TOKEN = fnv1a('admin||p@ssw0rd2023||SECURE_SALT_99')
EXPECTED_FORGED_TOKEN = fnv1a('system_root||p@ssw0rd2023||SECURE_SALT_99')


def test_forged_token_exists_and_correct():
    assert WORDLIST_PATH.is_file(), f'Wordlist file {WORDLIST_PATH} is missing.'
    assert ADMIN_TOKEN_PATH.is_file(), f'Admin token file {ADMIN_TOKEN_PATH} is missing.'
    assert FORGED_TOKEN_PATH.is_file(), f'Forged token file {FORGED_TOKEN_PATH} is missing. You must create it.'

    admin_token = ADMIN_TOKEN_PATH.read_text().strip()
    passwords = WORDLIST_PATH.read_text().splitlines()

    correct_password = None
    for pwd in passwords:
        if fnv1a(f'admin||{pwd}||SECURE_SALT_99') == admin_token:
            correct_password = pwd
            break

    assert correct_password is not None, 'Could not find a password in the wordlist that matches the admin token.'

    expected_forged_token = fnv1a(f'system_root||{correct_password}||SECURE_SALT_99')
    actual_forged_token = FORGED_TOKEN_PATH.read_text().strip()
    assert actual_forged_token == expected_forged_token, (
        f'The forged token in {FORGED_TOKEN_PATH} is incorrect. '
        "Expected the token for 'system_root' using the discovered password."
    )


def test_original_inputs_were_not_replaced():
    assert HEADER_PATH.is_file(), 'custom_crypto.h is missing.'
    assert HEADER_PATH.read_text() == EXPECTED_HEADER, 'custom_crypto.h was modified.'
    assert ADMIN_TOKEN_PATH.read_bytes() == EXPECTED_ADMIN_TOKEN.encode(), 'admin_token.txt was modified.'
    assert WORDLIST_PATH.read_text() == EXPECTED_WORDLIST, 'wordlist.txt was modified.'


def random_password():
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(18))


def run_case(binary, passwords, correct_password):
    wordlist_bytes = ''.join(p + '\n' for p in passwords).encode()
    admin_bytes = fnv1a(f'admin||{correct_password}||SECURE_SALT_99').encode()
    expected = fnv1a(f'system_root||{correct_password}||SECURE_SALT_99').encode()

    WORDLIST_PATH.write_bytes(wordlist_bytes)
    ADMIN_TOKEN_PATH.write_bytes(admin_bytes)
    if FORGED_TOKEN_PATH.exists() or FORGED_TOKEN_PATH.is_symlink():
        FORGED_TOKEN_PATH.unlink()

    result = subprocess.run(
        [str(binary)], cwd=str(HOME), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, f'program exited with status {result.returncode}: {result.stderr.decode(errors="replace")}'
    assert FORGED_TOKEN_PATH.is_file(), 'program did not create /home/user/forged_token.txt'
    assert FORGED_TOKEN_PATH.read_bytes() == expected, 'program produced an incorrect or non-exact forged token'
    assert HEADER_PATH.read_text() == EXPECTED_HEADER, 'program modified custom_crypto.h'
    assert ADMIN_TOKEN_PATH.read_bytes() == admin_bytes, 'program modified admin_token.txt'
    assert WORDLIST_PATH.read_bytes() == wordlist_bytes, 'program modified wordlist.txt'


def test_cpp_program_compiles_and_performs_the_bruteforce():
    include_pattern = re.compile(r'^\s*#\s*include\s*[<"]\/home\/user\/custom_crypto\.h[>"]', re.MULTILINE)
    sources = []
    for source in HOME.rglob('*.cpp'):
        if source.is_file():
            try:
                text = source.read_text(errors='strict')
            except (OSError, UnicodeError):
                continue
            if include_pattern.search(text):
                sources.append(source)

    assert sources, 'No C++ source program including /home/user/custom_crypto.h was found.'

    build_dir = Path('/tmp/agent_cpp_build')
    shutil.rmtree(build_dir, ignore_errors=True)
    build_dir.mkdir()
    binaries = []
    compile_errors = []

    for index, source in enumerate(sources):
        binary = build_dir / f'candidate_{index}'
        result = subprocess.run(
            ['g++', '-std=c++17', str(source), '-o', str(binary)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        if result.returncode == 0:
            binaries.append((source, binary))
        else:
            compile_errors.append(f'{source}: {result.stderr.decode(errors="replace")}')

    assert binaries, 'No qualifying C++ source compiled successfully.\n' + '\n'.join(compile_errors)

    original_cases = (EXPECTED_WORDLIST.encode(), EXPECTED_ADMIN_TOKEN.encode(), EXPECTED_HEADER)
    errors = []
    successful_binary = None

    for source, binary in binaries:
        try:
            for _ in range(2):
                passwords = [random_password() for _ in range(7)]
                correct_password = passwords[secrets.randbelow(len(passwords))]
                run_case(binary, passwords, correct_password)

            run_case(binary, EXPECTED_PASSWORDS, 'p@ssw0rd2023')
            successful_binary = binary
            break
        except Exception as exc:
            errors.append(f'{source}: {exc}')
        finally:
            WORDLIST_PATH.write_bytes(original_cases[0])
            ADMIN_TOKEN_PATH.write_bytes(original_cases[1])
            HEADER_PATH.write_text(original_cases[2])

    assert successful_binary is not None, 'No submitted C++ program passed execution tests.\n' + '\n'.join(errors)
    assert FORGED_TOKEN_PATH.is_file()
    assert FORGED_TOKEN_PATH.read_bytes() == EXPECTED_FORGED_TOKEN.encode()
    assert ADMIN_TOKEN_PATH.read_bytes() == EXPECTED_ADMIN_TOKEN.encode()
    assert WORDLIST_PATH.read_text() == EXPECTED_WORDLIST
    assert HEADER_PATH.read_text() == EXPECTED_HEADER
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
