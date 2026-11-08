#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tempfile


def derive_token_from_inputs():
    with open("/home/user/service.c", "r") as f:
        service_source = f.read()
    with open("/home/user/process_snaps.log", "r") as f:
        process_log = f.read()

    key_match = re.search(r'MASTER_KEY\s*=\s*"([^"]+)"', service_source)
    token_match = re.search(r'auth_helper\s+--token\s+([0-9a-fA-F]+)', process_log)
    assert key_match, "Could not derive MASTER_KEY from service.c"
    assert token_match, "Could not derive leaked ciphertext from process_snaps.log"

    key = key_match.group(1).encode()
    ciphertext = bytes.fromhex(token_match.group(1))
    return bytes(value ^ key[i % len(key)] for i, value in enumerate(ciphertext))


def test_decrypt_c_exists():
    file_path = "/home/user/decrypt.c"
    assert os.path.isfile(file_path), f"File not found: {file_path}. You must write the decryption logic in C."


def test_recovered_token():
    file_path = "/home/user/recovered_token.txt"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        content = f.read()

    expected_token = "SuperSecretAdminPassword99"
    assert content == expected_token, f"The recovered token is incorrect or contains extra characters/newlines. Expected '{expected_token}', got '{content}'."
    assert content.encode() == derive_token_from_inputs(), "The recovered token does not match the token derived from the supplied source and process log."


def test_token_hash():
    file_path = "/home/user/token_hash.txt"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_token = b"SuperSecretAdminPassword99"
    expected_hash = hashlib.sha256(expected_token).hexdigest()

    assert content == expected_hash, f"The token hash is incorrect. Expected '{expected_hash}', got '{content}'."


def test_decrypt_c_compiles_and_recovers_token_when_executed():
    source_path = "/home/user/decrypt.c"
    expected_token = derive_token_from_inputs()

    with open(source_path, "rb") as f:
        source = f.read()
    assert expected_token not in source, "decrypt.c must implement decryption rather than embed the recovered plaintext."

    output_path = "/home/user/recovered_token.txt"
    original_output = None
    if os.path.isfile(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    with tempfile.TemporaryDirectory() as temp_dir:
        executable = os.path.join(temp_dir, "decrypt_test")
        compile_result = subprocess.run(
            ["gcc", source_path, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_result.returncode == 0, f"decrypt.c did not compile successfully:\n{compile_result.stderr.decode(errors='replace')}"

        if os.path.exists(output_path):
            os.unlink(output_path)

        try:
            run_result = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            generated_file = None
            if os.path.isfile(output_path):
                with open(output_path, "rb") as f:
                    generated_file = f.read()

            assert run_result.returncode == 0, f"The compiled decrypt program exited with status {run_result.returncode}:\n{run_result.stderr.decode(errors='replace')}"
            produced_token = generated_file == expected_token or expected_token in run_result.stdout
            assert produced_token, "Executing the freshly compiled decrypt.c did not recover the token on stdout or in recovered_token.txt."
        finally:
            if original_output is not None:
                with open(output_path, "wb") as f:
                    f.write(original_output)
            elif os.path.exists(output_path):
                os.unlink(output_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
