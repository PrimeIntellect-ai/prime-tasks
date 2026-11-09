#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile


def run_decrypt():
    return subprocess.run(
        ["python3", "/home/user/decrypt.py"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=True,
    )


def test_decrypt_py_exists():
    path = "/home/user/decrypt.py"
    assert os.path.isfile(path), f"Expected {path} to exist as a file. The student must write their script here."


def test_script_programmatically_extracts_key_and_decrypts():
    cryptor = "/home/user/custom_cryptor"
    encrypted = "/home/user/stolen_data.enc"
    decrypted = "/home/user/decrypted.txt"

    key = secrets.token_bytes(8)
    expected = ("DYNAMIC_" + secrets.token_hex(24)).encode("ascii")
    ciphertext = bytes(value ^ key[index % 8] for index, value in enumerate(expected))
    key_initializer = ", ".join(f"0x{value:02x}" for value in key)

    source = f'''\n__attribute__((section(".keys"), used))\nconst unsigned char secret_key[8] = {{{key_initializer}}};\nint main(void) {{ return 73; }}\n'''

    with tempfile.TemporaryDirectory() as temp_dir:
        original_cryptor = os.path.join(temp_dir, "custom_cryptor.original")
        original_encrypted = os.path.join(temp_dir, "stolen_data.enc.original")
        os.replace(cryptor, original_cryptor)
        os.replace(encrypted, original_encrypted)

        try:
            source_path = os.path.join(temp_dir, "dynamic_cryptor.c")
            with open(source_path, "w", encoding="utf-8") as handle:
                handle.write(source)
            subprocess.run(
                ["gcc", source_path, "-o", cryptor],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
                check=True,
            )
            with open(encrypted, "wb") as handle:
                handle.write(ciphertext)

            if os.path.lexists(decrypted):
                os.unlink(decrypted)
            run_decrypt()

            assert os.path.isfile(decrypted), "decrypt.py did not create /home/user/decrypted.txt"
            with open(decrypted, "rb") as handle:
                actual = handle.read()
            assert actual == expected, (
                "decrypt.py did not extract the runtime-generated .keys section "
                "and decrypt the runtime-generated ciphertext correctly"
            )
        finally:
            if os.path.lexists(cryptor):
                os.unlink(cryptor)
            if os.path.lexists(encrypted):
                os.unlink(encrypted)
            os.replace(original_cryptor, cryptor)
            os.replace(original_encrypted, encrypted)

            if os.path.lexists(decrypted):
                os.unlink(decrypted)
            run_decrypt()


def test_decrypted_txt_exists_and_correct():
    path = "/home/user/decrypted.txt"
    assert os.path.isfile(path), f"Expected {path} to exist as a file containing the decrypted data."

    expected_content = "FLAG{VULNERABLE_ELF_XOR_CRYPTO_BROKEN}"

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert content == expected_content, (
        f"Content of {path} is incorrect.\n"
        f"Expected: {expected_content!r}\n"
        f"Got: {content!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
