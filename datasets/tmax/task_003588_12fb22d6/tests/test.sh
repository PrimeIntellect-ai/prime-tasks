#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import uuid
import pytest


def test_phase1_world_readable():
    output_file = "/home/user/world_readable.txt"
    assert os.path.exists(output_file), f"Phase 1 output file {output_file} is missing."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["file2.sql", "file4.log"]
    assert lines == expected, f"Expected {output_file} to contain {expected}, but got {lines}."


def test_phase2_fixed_keys():
    output_file = "/home/user/fixed_keys.txt"
    assert os.path.exists(output_file), f"Phase 2 output file {output_file} is missing."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["id_ecdsa", "id_rsa_2"]
    assert lines == expected, f"Expected {output_file} to contain {expected}, but got {lines}."

    ssh_keys_dir = "/home/user/ssh_keys"
    for key_file in ["id_rsa_1", "id_rsa_2", "id_ecdsa"]:
        full_path = os.path.join(ssh_keys_dir, key_file)
        assert os.path.exists(full_path), f"SSH key {full_path} is missing."

        mode = os.stat(full_path).st_mode
        actual_perm = stat.S_IMODE(mode)
        assert actual_perm == 0o600, f"File {full_path} has incorrect permissions. Expected 0o600, got {oct(actual_perm)}."


def decrypt_file(path):
    helper = r'''
package main

import (
    "crypto/aes"
    "crypto/cipher"
    "fmt"
    "os"
)

func main() {
    if len(os.Args) != 3 {
        os.Exit(10)
    }
    key, err := os.ReadFile(os.Args[1])
    if err != nil {
        os.Exit(11)
    }
    enc, err := os.ReadFile(os.Args[2])
    if err != nil {
        os.Exit(12)
    }
    block, err := aes.NewCipher(key)
    if err != nil {
        os.Exit(13)
    }
    gcm, err := cipher.NewGCM(block)
    if err != nil {
        os.Exit(14)
    }
    if gcm.NonceSize() != 12 || len(enc) < 12+gcm.Overhead() {
        os.Exit(15)
    }
    plaintext, err := gcm.Open(nil, enc[:12], enc[12:], nil)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(16)
    }
    if _, err := os.Stdout.Write(plaintext); err != nil {
        os.Exit(17)
    }
}
'''
    with tempfile.NamedTemporaryFile(mode="w", suffix=".go", delete=False) as f:
        f.write(helper)
        helper_path = f.name
    try:
        result = subprocess.run(
            ["go", "run", helper_path, "/home/user/encryption_key.bin", path],
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Unable to decrypt generated output: {result.stderr.decode(errors='replace')}"
        return result.stdout
    finally:
        os.remove(helper_path)


def derive_redaction(source):
    header = "-----BEGIN OPENSSH PRIVATE KEY-----"
    footer = "-----END OPENSSH PRIVATE KEY-----"
    output = []
    in_key = False

    for line in source.splitlines(keepends=True):
        ending = "\n" if line.endswith("\n") else ""
        content = line[:-1] if ending else line

        if not in_key and content == header:
            output.append("[PRIVATE KEY REDACTED]")
            in_key = True
            continue
        if in_key:
            if content == footer:
                output.append(ending)
                in_key = False
            continue

        marker = "Password: "
        marker_pos = content.find(marker)
        if marker_pos != -1:
            content = content[:marker_pos + len(marker)] + "[REDACTED]"
        output.append(content + ending)

    return "".join(output)


def test_phase3_encryption_and_redaction():
    enc_file = "/home/user/secure_audit.enc"
    key_file = "/home/user/encryption_key.bin"
    source_file = "/home/user/system.log"
    program_file = "/home/user/redactor.go"

    assert os.path.exists(enc_file), f"Encrypted audit file {enc_file} is missing."
    assert os.path.exists(key_file), f"Encryption key file {key_file} is missing."

    go_verifier = """
package main

import (
    "crypto/aes"
    "crypto/cipher"
    "fmt"
    "io/ioutil"
    "os"
)

func main() {
    key, err := ioutil.ReadFile("/home/user/encryption_key.bin")
    if err != nil {
        fmt.Println("Failed to read key")
        os.Exit(1)
    }
    enc, err := ioutil.ReadFile("/home/user/secure_audit.enc")
    if err != nil {
        fmt.Println("Failed to read encrypted file")
        os.Exit(1)
    }

    block, err := aes.NewCipher(key)
    if err != nil {
        fmt.Println("Failed to create cipher")
        os.Exit(1)
    }
    gcm, err := cipher.NewGCM(block)
    if err != nil {
        fmt.Println("Failed to create GCM")
        os.Exit(1)
    }

    nonceSize := gcm.NonceSize()
    if len(enc) < nonceSize {
        fmt.Println("Encrypted file too short")
        os.Exit(1)
    }
    nonce, ciphertext := enc[:nonceSize], enc[nonceSize:]

    plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
    if err != nil {
        fmt.Println("Decryption failed (authentication or format error)")
        os.Exit(1)
    }

    expected := `System boot initiated.
User login Password: [REDACTED]
Connecting to remote server...
Error: auth failed.
Generating diagnostic dump.
Included keys:
[PRIVATE KEY REDACTED]
Diagnostic complete.
Admin authentication Password: [REDACTED]
End of log.
`
    if string(plaintext) != expected {
        fmt.Println("Redaction mismatch. Got:\\n" + string(plaintext))
        os.Exit(2)
    }
}
"""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".go", delete=False) as f:
        f.write(go_verifier)
        temp_go_file = f.name

    try:
        result = subprocess.run(["go", "run", temp_go_file], capture_output=True, text=True, timeout=30)
        if result.returncode == 1:
            pytest.fail(f"Decryption failed: {result.stdout.strip()}")
        elif result.returncode == 2:
            pytest.fail(f"Redaction verification failed: {result.stdout.strip()}")
        elif result.returncode != 0:
            pytest.fail(f"Go verification script failed unexpectedly: {result.stderr.strip()}")
    finally:
        os.remove(temp_go_file)

    assert os.path.isfile(program_file), f"Required Go program {program_file} is missing or is not a file."
    assert os.path.getsize(program_file) > 0, f"Required Go program {program_file} is empty."

    original_source = open(source_file, "rb").read()
    original_enc = open(enc_file, "rb").read()
    token = uuid.uuid4().hex
    dynamic_source = (
        f"Audit case {token}\n"
        f"Account Password: secret-{token}\n"
        "Unrelated line remains unchanged.\n"
        "-----BEGIN OPENSSH PRIVATE KEY-----\n"
        f"random-key-material-{token}\n"
        f"more-random-key-material-{token[::-1]}\n"
        "-----END OPENSSH PRIVATE KEY-----\n"
        f"Final Password: ending-{token}\n"
        f"Completed {token}.\n"
    )
    expected_dynamic = derive_redaction(dynamic_source).encode()

    try:
        with open(source_file, "wb") as f:
            f.write(dynamic_source.encode())

        outputs = []
        for _ in range(2):
            result = subprocess.run(
                ["go", "run", program_file],
                capture_output=True,
                text=True,
                timeout=30,
                cwd="/home/user",
            )
            assert result.returncode == 0, (
                f"Running {program_file} failed with exit code {result.returncode}: "
                f"{result.stderr.strip()}"
            )
            assert os.path.isfile(enc_file), "The Go program did not create secure_audit.enc."
            encrypted = open(enc_file, "rb").read()
            assert len(encrypted) >= 12 + 16, "Generated AES-GCM output is too short."
            assert decrypt_file(enc_file) == expected_dynamic, (
                "The Go program did not read and correctly redact the verifier-supplied log."
            )
            outputs.append(encrypted)

        assert outputs[0][:12] != outputs[1][:12], (
            "The program reused a nonce; it must generate a fresh random 12-byte nonce for each encryption."
        )
    finally:
        with open(source_file, "wb") as f:
            f.write(original_source)
        with open(enc_file, "wb") as f:
            f.write(original_enc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
