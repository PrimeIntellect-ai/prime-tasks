#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import struct
import shutil
import subprocess
import tempfile

BASE = "/home/user/packet_analysis"
CAPTURE = os.path.join(BASE, "capture.bin")
PEM_PREFIX = b"-----BEGIN CERTIFICATE-----"


def packet_payload(path=CAPTURE):
    data = open(path, "rb").read()
    assert len(data) >= 8, "capture.bin is truncated"
    assert data[:4] == b"PCKT", "capture.bin has invalid magic"
    length = struct.unpack("<I", data[4:8])[0]
    assert len(data) == 8 + length, "capture.bin length field is inconsistent"
    return data[8:]


def expected_plaintext():
    ciphertext = packet_payload()
    assert len(ciphertext) >= len(PEM_PREFIX)
    known_stream = bytes(a ^ b for a, b in zip(ciphertext, PEM_PREFIX))
    period = None
    for p in range(1, len(known_stream) + 1):
        if all(known_stream[i] == known_stream[i % p] for i in range(len(known_stream))):
            period = p
            break
    assert period is not None
    key = known_stream[:period]
    return bytes(value ^ key[i % period] for i, value in enumerate(ciphertext))


def run_parser(executable):
    with tempfile.TemporaryDirectory() as td:
        payload = os.urandom(4096)
        packet = os.path.join(td, "packet.bin")
        output = os.path.join(td, "payload.enc")
        with open(packet, "wb") as f:
            f.write(b"PCKT")
            f.write(struct.pack("<I", len(payload)))
            f.write(payload)
        result = subprocess.run([executable, packet, output], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isfile(output)
        assert open(output, "rb").read() == payload


def test_parser_fixed_exists_and_executable():
    path = os.path.join(BASE, "parser_fixed")
    assert os.path.isfile(path), f"File {path} does not exist. Did you compile parser.c?"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    run_parser(path)


def test_fixed_parser_source_compiles_cleanly_and_works():
    source = os.path.join(BASE, "parser.c")
    assert os.path.isfile(source)
    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "parser")
        result = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", source, "-o", executable],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        run_parser(executable)


def test_payload_enc_exists_and_is_parser_output():
    path = os.path.join(BASE, "payload.enc")
    assert os.path.isfile(path), f"File {path} does not exist. Did you run parser_fixed?"
    assert os.path.getsize(path) > 0, f"File {path} is empty."
    assert open(path, "rb").read() == packet_payload()


def test_decrypt_c_exists_compiles_cleanly_and_runs():
    source = os.path.join(BASE, "decrypt.c")
    assert os.path.isfile(source), f"File {source} does not exist. Did you write the decryption program?"
    assert os.path.getsize(source) > 0, f"File {source} is empty."

    expected = expected_plaintext()
    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "decrypt")
        result = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", source, "-o", executable],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        assert result.returncode == 0, result.stderr.decode(errors="replace")

        local_input = os.path.join(td, "payload.enc")
        local_output = os.path.join(td, "extracted.crt")
        shutil.copyfile(os.path.join(BASE, "payload.enc"), local_input)

        invocations = ([executable, local_input, local_output],
                       [executable, local_input],
                       [executable])
        produced = False
        for command in invocations:
            if os.path.exists(local_output):
                os.unlink(local_output)
            try:
                subprocess.run(command, cwd=td, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=10)
            except subprocess.TimeoutExpired:
                continue
            if os.path.isfile(local_output) and open(local_output, "rb").read() == expected:
                produced = True
                break
        assert produced, "The compiled decrypt.c program did not decrypt payload.enc to extracted.crt"


def test_extracted_crt_exists_and_valid():
    path = os.path.join(BASE, "extracted.crt")
    assert os.path.isfile(path), f"File {path} does not exist. Did you decrypt the payload?"
    content = open(path, "rb").read()
    assert content.startswith(PEM_PREFIX), f"File {path} does not appear to be a valid PEM certificate."
    assert content == expected_plaintext(), "extracted.crt is not the decrypted captured payload"
    result = subprocess.run(["openssl", "x509", "-in", path, "-noout"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, "extracted.crt is not a valid TLS certificate"


def test_fingerprint_matches():
    cert_path = os.path.join(BASE, "extracted.crt")
    actual_path = os.path.join(BASE, "fingerprint.txt")
    assert os.path.isfile(actual_path), f"File {actual_path} does not exist."

    result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-fingerprint", "-sha256"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    expected_fingerprint = result.stdout.strip().split("=", 1)[1]

    raw = open(actual_path, "r").read()
    actual_fingerprint = raw.strip()
    assert re.fullmatch(r"[0-9A-F]{2}(?::[0-9A-F]{2}){31}", actual_fingerprint), \
        "fingerprint.txt must contain only an uppercase colon-separated SHA-256 fingerprint"
    assert raw in (actual_fingerprint, actual_fingerprint + "\n"), \
        "fingerprint.txt contains extra content"
    assert actual_fingerprint == expected_fingerprint, \
        f"Fingerprint in {actual_path} does not match the decrypted certificate."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
