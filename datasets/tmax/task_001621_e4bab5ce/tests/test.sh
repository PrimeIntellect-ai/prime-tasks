#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile

LOG_PATH = "/home/user/evidence/network_log.txt"
SOURCE_PATH = "/home/user/decoder.cpp"
DECODER_PATH = "/home/user/decoder"
SECRET_PATH = "/home/user/evidence/decrypted_secret.txt"

CANONICAL_LOG = """192.168.1.50 10.0.0.1 22 AUTH_SUCCESS user_login
192.168.1.100 10.0.0.1 8080 AUTH_FAILED invalid
10.0.0.5 10.0.0.1 80 SYSTEM_PING ok
192.168.1.100 10.0.0.1 8080 AUTH_SUCCESS T0k3nM4st3r
192.168.1.50 10.0.0.1 22 CMD_EXEC ls_-la
192.168.1.100 10.0.0.1 8080 EXFIL 177f25752709713d207a3318
192.168.1.100 10.0.0.1 8080 CMD_EXEC tar_czf_data
192.168.1.100 10.0.0.1 8080 EXFIL 6f24632b1f75273d7c3c0b64
10.0.0.5 10.0.0.1 80 SYSTEM_PING ok
192.168.1.100 10.0.0.1 8080 EXFIL 39762f0967273b7d370b7128
192.168.1.100 10.0.0.1 8080 EXFIL 67271b71
"""

ORIGINAL_TOKEN = "T0k3nM4st3r"
ORIGINAL_CHUNKS = [
    "177f25752709713d207a3318",
    "6f24632b1f75273d7c3c0b64",
    "39762f0967273b7d370b7128",
    "67271b71",
]


def parse_and_decrypt(log_text):
    token = None
    chunks = []
    for line in log_text.splitlines():
        parts = line.split()
        if len(parts) >= 5 and parts[0] == "192.168.1.100":
            if parts[3] == "AUTH_SUCCESS":
                token = parts[4]
            elif parts[3] == "EXFIL":
                chunks.append(parts[4])
    assert token and chunks
    raw = bytes.fromhex("".join(chunks))
    key = token.encode()
    return bytes(b ^ key[i % len(key)] for i, b in enumerate(raw)).decode()


EXPECTED = parse_and_decrypt(CANONICAL_LOG)


def test_01_decoder_cpp_exists():
    assert os.path.isfile(SOURCE_PATH), "/home/user/decoder.cpp is missing. You must write the C++ program at this path."


def test_02_decoder_executable_exists():
    assert os.path.isfile(DECODER_PATH), "/home/user/decoder executable is missing. Did you compile your C++ program?"
    assert os.access(DECODER_PATH, os.X_OK), "/home/user/decoder is not executable."
    with open(DECODER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/decoder must be a compiled executable."


def test_03_original_evidence_is_intact():
    assert os.path.isfile(LOG_PATH), "/home/user/evidence/network_log.txt is missing."
    with open(LOG_PATH, "r") as f:
        actual = f.read()
    assert actual == CANONICAL_LOG, "The supplied network evidence was modified."


def test_04_decrypted_secret_exists():
    assert os.path.isfile(SECRET_PATH), "/home/user/evidence/decrypted_secret.txt is missing. You must save the final decrypted plaintext to this file."


def test_05_decrypted_secret_content():
    with open(SECRET_PATH, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED, "Decrypted secret content is incorrect. Ensure you correctly parsed the exfiltrated chunks and XOR decrypted them with the correct token."


def run_program(path, ciphertext, token, expected):
    invocations = [
        ([], ""),
        ([ciphertext, token], ""),
        ([token, ciphertext], ""),
        ([], ciphertext + "\n" + token + "\n"),
        ([], token + "\n" + ciphertext + "\n"),
    ]
    for args, stdin_data in invocations:
        with open(SECRET_PATH, "w") as f:
            f.write("verification-decoy")
        try:
            proc = subprocess.run(
                [path] + args,
                input=stdin_data,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=3,
            )
        except (subprocess.TimeoutExpired, OSError):
            continue
        output_ok = proc.returncode == 0 and proc.stdout.strip() == expected
        file_ok = False
        try:
            with open(SECRET_PATH, "r") as f:
                file_ok = f.read().strip() == expected
        except OSError:
            pass
        if output_ok or file_ok:
            return True
    return False


def make_log(token, chunks):
    lines = CANONICAL_LOG.splitlines()
    result = []
    chunk_index = 0
    for line in lines:
        parts = line.split()
        if len(parts) >= 5 and parts[0] == "192.168.1.100" and parts[3] == "AUTH_SUCCESS":
            parts[4] = token
            line = " ".join(parts)
        elif len(parts) >= 5 and parts[0] == "192.168.1.100" and parts[3] == "EXFIL":
            parts[4] = chunks[chunk_index]
            chunk_index += 1
            line = " ".join(parts)
        result.append(line)
    return "\n".join(result) + "\n"


def transformed_source(source, token, chunks):
    replacements = [(ORIGINAL_TOKEN, token)] + list(zip(ORIGINAL_CHUNKS, chunks))
    for old, new in replacements:
        source = source.replace(old, new)
        source = source.replace(old.upper(), new.upper())
    return source


def test_06_decoder_actually_decodes_hex_and_xor():
    with open(SOURCE_PATH, "r") as f:
        original_source = f.read()
    with open(SECRET_PATH, "r") as f:
        original_secret = f.read()

    canonical_hex = "".join(ORIGINAL_CHUNKS)
    try:
        assert run_program(DECODER_PATH, canonical_hex, ORIGINAL_TOKEN, EXPECTED), \
            "The compiled decoder did not produce the decrypted plaintext when executed."

        rng = random.SystemRandom()
        alphabet = string.ascii_letters + string.digits + "_"
        for _ in range(2):
            token = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(len(ORIGINAL_TOKEN)))
            plaintext = "".join(rng.choice(alphabet) for _ in range(len(bytes.fromhex(canonical_hex))))
            key = token.encode()
            ciphertext = bytes(ord(ch) ^ key[i % len(key)] for i, ch in enumerate(plaintext)).hex()

            lengths = [len(c) for c in ORIGINAL_CHUNKS]
            chunks = []
            pos = 0
            for length in lengths:
                chunks.append(ciphertext[pos:pos + length])
                pos += length

            test_log = make_log(token, chunks)
            with open(LOG_PATH, "w") as f:
                f.write(test_log)

            source = transformed_source(original_source, token, chunks)
            with tempfile.TemporaryDirectory() as td:
                test_cpp = os.path.join(td, "decoder.cpp")
                test_bin = os.path.join(td, "decoder")
                with open(test_cpp, "w") as f:
                    f.write(source)
                compiled = subprocess.run(
                    ["g++", "-std=c++17", test_cpp, "-o", test_bin],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20,
                )
                assert compiled.returncode == 0, "The submitted decoder.cpp could not be compiled by the verifier."
                assert run_program(test_bin, ciphertext, token, plaintext), \
                    "decoder.cpp does not correctly perform hex decoding and repeating-key XOR on independent test data."
    finally:
        with open(LOG_PATH, "w") as f:
            f.write(CANONICAL_LOG)
        with open(SECRET_PATH, "w") as f:
            f.write(original_secret)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
