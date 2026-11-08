#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
SOURCE = HOME / 'decryptor.c'
EVIDENCE = HOME / 'evidence.bin'
DECRYPTED = HOME / 'decrypted.log'
EXECUTABLE = Path('/tmp/submission_decryptor')
HEADER = b'CRIME_LOG_START{v1.0}\n'
MULTIPLIER = 0x5D588B65
INCREMENT = 0x2BCD
MASK = 0xFFFFFFFF


def crypt(data, seed):
    state = seed
    output = bytearray()
    for value in data:
        state = (state * MULTIPLIER + INCREMENT) & MASK
        output.append(value ^ (state >> 24))
    return bytes(output)


def recover_seed(ciphertext, known_plaintext):
    target = bytes(a ^ b for a, b in zip(ciphertext, known_plaintext))
    for seed in range(1 << 32):
        state = seed
        for expected in target:
            state = (state * MULTIPLIER + INCREMENT) & MASK
            if (state >> 24) != expected:
                break
        else:
            return seed
    raise AssertionError('No seed produces the documented known-plaintext header')


def compile_submission():
    mode = os.lstat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f'{SOURCE} is not a regular C source file.'
    result = subprocess.run(
        ['gcc', '-O3', '-std=c11', '-fopenmp', '-pthread', str(SOURCE), '-o', str(EXECUTABLE)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f'decryptor.c did not compile:\n{result.stderr}'
    assert EXECUTABLE.is_file(), 'Compiling decryptor.c did not produce an executable.'


def run_submission():
    # The instruction fixes the input and output paths but does not prescribe a CLI.
    # Accept the common no-argument and path-argument interfaces.
    invocations = [
        [str(EXECUTABLE)],
        [str(EXECUTABLE), str(EVIDENCE)],
        [str(EXECUTABLE), str(EVIDENCE), str(DECRYPTED)],
    ]
    failures = []
    for command in invocations:
        DECRYPTED.unlink(missing_ok=True)
        try:
            result = subprocess.run(
                command,
                cwd=str(HOME),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{' '.join(command)} timed out")
            continue
        if result.returncode == 0 and DECRYPTED.is_file():
            return
        failures.append(
            f"{' '.join(command)} returned {result.returncode}; stderr={result.stderr!r}"
        )
    raise AssertionError('The compiled decryptor did not create decrypted.log. ' + '; '.join(failures))


def test_00_compile_execute_and_decrypt_complete_files():
    assert SOURCE.exists(), f'File {SOURCE} is missing. You must write the brute-force tool in C.'
    compile_submission()

    original_ciphertext = EVIDENCE.read_bytes()
    original_seed = recover_seed(original_ciphertext, HEADER)
    original_plaintext = crypt(original_ciphertext, original_seed)
    assert original_plaintext.startswith(HEADER)

    # First prove the submitted program itself recreates the complete original output.
    run_submission()
    assert DECRYPTED.read_bytes() == original_plaintext, \
        'decrypted.log is not the complete decryption of evidence.bin.'

    # Exercise the compiled program on a fresh ciphertext and seed so a fabricated
    # fixed answer or a decryptor specialized to the supplied evidence cannot pass.
    random_seed = secrets.randbelow(31338)
    token = secrets.token_hex(16)
    test_plaintext = (
        HEADER
        + b'2026-09-11 08:00:00 - Verification test started\n'
        + f'FLAG: {token}\n'.encode('ascii')
        + b'2026-09-11 08:00:01 - Verification test complete\n'
        + b'CRIME_LOG_END\n'
    )
    test_ciphertext = crypt(test_plaintext, random_seed)

    try:
        EVIDENCE.write_bytes(test_ciphertext)
        run_submission()
        assert DECRYPTED.read_bytes() == test_plaintext, \
            'The compiled decryptor failed to recover a fresh encrypted file exactly.'
    finally:
        EVIDENCE.write_bytes(original_ciphertext)

    # Leave the required artifact in its requested final state.
    run_submission()
    assert DECRYPTED.read_bytes() == original_plaintext


def test_solution_txt_exists_and_correct():
    path = '/home/user/solution.txt'
    assert os.path.exists(path), f'File {path} is missing.'
    assert os.path.isfile(path), f'{path} is not a file.'

    with open(path, 'r') as f:
        content = f.read().strip()

    # Recompute the expected hash from the known flag string to be robust
    expected_flag = '9a8b7c6d5e4f3g2h1i0j'
    expected_hash = hashlib.sha256(expected_flag.encode('utf-8')).hexdigest()

    assert content == expected_hash, f'The hash in {path} is incorrect. Expected {expected_hash}, got {content}.'


def test_decryptor_c_exists():
    path = '/home/user/decryptor.c'
    assert os.path.exists(path), f'File {path} is missing. You must write the brute-force tool in C.'
    assert os.path.isfile(path), f'{path} is not a file.'

    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    assert len(content.strip()) > 0, f'File {path} is empty.'


def test_decrypted_log_exists_and_contains_flag():
    path = '/home/user/decrypted.log'
    assert os.path.exists(path), f'File {path} is missing.'
    assert os.path.isfile(path), f'{path} is not a file.'

    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    assert 'CRIME_LOG_START{v1.0}' in content, 'The decrypted log does not contain the expected header.'
    assert 'FLAG: 9a8b7c6d5e4f3g2h1i0j' in content, 'The decrypted log does not contain the expected FLAG string.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
