#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import secrets
import string
import subprocess


def test_decrypted_policy_exists_and_correct():
    decrypted_path = "/home/user/decrypted_policy.txt"
    assert os.path.exists(decrypted_path), f"File {decrypted_path} does not exist. Did you save the decrypted output?"
    assert os.path.isfile(decrypted_path), f"Path {decrypted_path} is not a file."

    with open(decrypted_path, "r") as f:
        content = f.read()

    expected_content = "POLICY=DENY_UNTRUSTED_REGISTRIES"
    assert content == expected_content, f"The decrypted policy content is incorrect. Expected exactly '{expected_content}', but got '{content}'"


def test_decoder_rs_exists():
    decoder_path = "/home/user/decoder.rs"
    assert os.path.exists(decoder_path), f"Rust program {decoder_path} does not exist. Did you write the solution in Rust?"
    assert os.path.isfile(decoder_path), f"Path {decoder_path} is not a file."


def test_decoder_compiles_and_decrypts_derived_payloads():
    decoder_path = "/home/user/decoder.rs"
    payload_path = "/home/user/payload.txt"
    decrypted_path = "/home/user/decrypted_policy.txt"
    binary_path = "/tmp/submitted_decoder"

    compile_result = subprocess.run(
        ["rustc", "--edition=2021", decoder_path, "-o", binary_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "decoder.rs did not compile successfully:\n"
        + compile_result.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(binary_path), "Compiling decoder.rs did not produce an executable."

    subject = subprocess.run(
        ["openssl", "x509", "-in", "/home/user/policy.crt", "-noout", "-subject", "-nameopt", "RFC2253"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        text=True,
    ).stdout
    match = re.search(r"(?:^|,)CN=([^,]+)", subject.removeprefix("subject=").strip())
    assert match, "Could not derive the certificate Common Name for behavioral testing."
    key = match.group(1).encode("utf-8")
    assert key, "The certificate Common Name is empty."

    original_payload = open(payload_path, "rb").read()
    original_decrypted = open(decrypted_path, "rb").read()

    alphabet = string.ascii_letters + string.digits + "_=-"
    plaintexts = [
        ("DYNAMIC_POLICY_" + "".join(secrets.choice(alphabet) for _ in range(31))).encode(),
        ("WRAP_TEST_" + "".join(secrets.choice(alphabet) for _ in range(79))).encode(),
    ]

    try:
        for plaintext in plaintexts:
            ciphertext = bytes(byte ^ key[i % len(key)] for i, byte in enumerate(plaintext))
            with open(payload_path, "wb") as f:
                f.write(base64.b64encode(ciphertext))

            if os.path.lexists(decrypted_path):
                os.remove(decrypted_path)

            run_result = subprocess.run(
                [binary_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
            )
            assert run_result.returncode == 0, (
                "The compiled decoder failed when run on a derived payload:\n"
                + run_result.stderr.decode("utf-8", errors="replace")
            )

            if os.path.isfile(decrypted_path):
                actual = open(decrypted_path, "rb").read()
            else:
                actual = run_result.stdout
                if actual.endswith(b"\r\n"):
                    actual = actual[:-2]
                elif actual.endswith(b"\n"):
                    actual = actual[:-1]

            assert actual == plaintext, (
                "The compiled Rust decoder did not correctly decrypt a derived payload "
                "using the certificate CN as a repeating XOR key."
            )
    finally:
        with open(payload_path, "wb") as f:
            f.write(original_payload)
        with open(decrypted_path, "wb") as f:
            f.write(original_decrypted)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
