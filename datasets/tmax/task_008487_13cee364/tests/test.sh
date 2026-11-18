#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_rust_solution.py
import hashlib
import os
import re
import secrets
import subprocess
from pathlib import Path

HOME = Path('/home/user')
TRAFFIC = HOME / 'traffic.bin'
SECRET = HOME / 'secret.txt'
EXPECTED = b'TELE_CRITICAL_SYSTEM_ALERT_FLAG{lcg_stream_broken_1337}'
original_traffic = TRAFFIC.read_bytes()


def source_uses_obvious_parameter_bruteforce(text):
    # Reject direct exhaustive iteration over named LCG parameters while allowing
    # ordinary loops over payload bytes and algebraic helper routines.
    pattern = re.compile(
        r'for\s+(?:mut\s+)?(?:a|c|candidate_a|candidate_c|multiplier|increment)\s+in\s+'
        r'0(?:u(?:8|16|32|64|size))?\s*\.\.= ?\s*(?:255|256)(?:u(?:8|16|32|64|size))?',
        re.IGNORECASE,
    )
    compact = re.sub(r'\s+', ' ', text)
    return bool(pattern.search(compact))


def collect_candidates():
    candidates = []
    cargo_roots = []

    for manifest in sorted(HOME.rglob('Cargo.toml')):
        if 'target' in manifest.parts or '.cargo' in manifest.parts:
            continue
        root = manifest.parent
        sources = [p for p in root.rglob('*.rs') if 'target' not in p.parts]
        if sources:
            candidates.append(('cargo', manifest, sources))
            cargo_roots.append(root)

    for source in sorted(HOME.rglob('*.rs')):
        if 'target' in source.parts or '.cargo' in source.parts:
            continue
        if any(source == root or root in source.parents for root in cargo_roots):
            continue
        candidates.append(('rustc', source, [source]))

    return candidates


def make_runner(candidate, index):
    kind, path, sources = candidate
    combined_source = '\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in sources)
    if source_uses_obvious_parameter_bruteforce(combined_source):
        return None

    if kind == 'cargo':
        build = subprocess.run(
            ['cargo', 'build', '--quiet', '--manifest-path', str(path)],
            cwd=str(path.parent), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=120,
        )
        if build.returncode != 0:
            return None

        def run():
            return subprocess.run(
                ['cargo', 'run', '--quiet', '--manifest-path', str(path)],
                cwd=str(path.parent), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=30,
            )
        return run

    binary = Path(f'/tmp/submitted_rust_{index}')
    build = subprocess.run(
        ['rustc', '--edition=2021', str(path), '-o', str(binary)],
        cwd=str(path.parent), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=120,
    )
    if build.returncode != 0:
        return None

    def run():
        return subprocess.run(
            [str(binary)], cwd=str(path.parent),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
        )
    return run


def encrypt_capture(plaintext, k0, a, c):
    encrypted = bytearray()
    k = k0
    for byte in plaintext:
        encrypted.append(byte ^ k)
        k = (a * k + c) % 256
    return hashlib.sha256(plaintext).digest() + bytes(encrypted)


def remove_secret():
    try:
        SECRET.unlink()
    except FileNotFoundError:
        pass


def output_matches(expected):
    if not SECRET.is_file():
        return False
    try:
        return SECRET.read_text(encoding='utf-8').strip().encode() == expected
    except (OSError, UnicodeError):
        return False


def exercise(runner):
    # Randomized captures prevent a hardcoded plaintext writer from passing.
    for case in range(3):
        k0 = secrets.randbelow(256)
        a = secrets.choice([x for x in range(3, 256, 2) if x != 17])
        c = secrets.choice(list(range(1, 256, 2)))
        token = secrets.token_hex(12).encode('ascii')
        plaintext = b'TELE_DYNAMIC_CASE_' + str(case).encode() + b'_FLAG{' + token + b'}'
        capture = encrypt_capture(plaintext, k0, a, c)

        TRAFFIC.write_bytes(capture)
        remove_secret()
        result = runner()
        if result.returncode != 0 or not output_matches(plaintext):
            return False

        # A mismatching checksum must not be accepted or written as plaintext.
        bad_checksum = bytes([capture[0] ^ 1]) + capture[1:]
        TRAFFIC.write_bytes(bad_checksum)
        remove_secret()
        runner()
        if SECRET.exists():
            return False

        # Likewise, ciphertext corruption must be detected by SHA-256 checking.
        bad_ciphertext = bytearray(capture)
        bad_ciphertext[-1] ^= 1
        TRAFFIC.write_bytes(bytes(bad_ciphertext))
        remove_secret()
        runner()
        if SECRET.exists():
            return False

    # Run the submitted Rust program on the original required capture. The
    # original exact-content assertions are performed separately below.
    TRAFFIC.write_bytes(original_traffic)
    remove_secret()
    result = runner()
    return result.returncode == 0 and output_matches(EXPECTED)


try:
    candidates = collect_candidates()
    assert candidates, 'No Rust source or Cargo project found under /home/user'

    passed = False
    for index, candidate in enumerate(candidates):
        try:
            runner = make_runner(candidate, index)
            if runner is not None and exercise(runner):
                passed = True
                break
        except (OSError, subprocess.SubprocessError, UnicodeError):
            continue

    assert passed, 'No submitted Rust program passed execution, decryption, and checksum tests'
finally:
    TRAFFIC.write_bytes(original_traffic)
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

SECRET_TXT_PATH = "/home/user/secret.txt"
EXPECTED_PLAINTEXT = "TELE_CRITICAL_SYSTEM_ALERT_FLAG{lcg_stream_broken_1337}"

def test_secret_txt_exists():
    """Verify that the secret.txt file exists."""
    assert os.path.exists(SECRET_TXT_PATH), f"Missing file: {SECRET_TXT_PATH}"
    assert os.path.isfile(SECRET_TXT_PATH), f"Not a file: {SECRET_TXT_PATH}"

def test_secret_txt_content():
    """Verify that the secret.txt file contains the correct decrypted plaintext."""
    with open(SECRET_TXT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == EXPECTED_PLAINTEXT, f"The content of {SECRET_TXT_PATH} is incorrect. Expected: '{EXPECTED_PLAINTEXT}', Got: '{content}'"
TEST_EOF

if python3 /tmp/verify_rust_solution.py 2>&1 && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
