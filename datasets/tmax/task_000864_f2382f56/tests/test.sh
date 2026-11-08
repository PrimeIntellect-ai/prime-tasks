#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path


def test_final_state_and_decryptor_behavior():
    recovered_path = Path("/home/user/recovered.txt")
    script_path = Path("/home/user/decrypt.go")

    # Preserve the original verifier assertions.
    assert recovered_path.is_file(), f"File not found: {recovered_path}"
    content = recovered_path.read_text().strip()
    expected_flag = "FLAG{0p3n_r3d1r3ct_t0_c0mpr0m1s3}"
    assert content == expected_flag, (
        f"Content of {recovered_path} is incorrect. "
        f"Expected '{expected_flag}', got '{content}'"
    )
    assert script_path.is_file(), f"Go script not found: {script_path}"

    # Build a fresh authenticated blob using the session from access.log and an
    # unpredictable PIN/plaintext, then require the submitted Go program to
    # recover it. This rejects constant-output and empty-Go-file submissions.
    helper_source = r'''
package main

import (
    "crypto/aes"
    "crypto/cipher"
    "crypto/rand"
    "crypto/sha256"
    "fmt"
    "io"
    "os"
)

func main() {
    if len(os.Args) != 4 {
        panic("usage: make_blob PIN SESSION OUTPUT")
    }
    plaintext, err := io.ReadAll(os.Stdin)
    if err != nil {
        panic(err)
    }
    key := sha256.Sum256([]byte(os.Args[1] + os.Args[2]))
    block, err := aes.NewCipher(key[:])
    if err != nil {
        panic(err)
    }
    gcm, err := cipher.NewGCM(block)
    if err != nil {
        panic(err)
    }
    nonce := make([]byte, gcm.NonceSize())
    if _, err := rand.Read(nonce); err != nil {
        panic(err)
    }
    output := append(nonce, gcm.Seal(nil, nonce, plaintext, nil)...)
    if err := os.WriteFile(os.Args[3], output, 0644); err != nil {
        panic(err)
    }
    fmt.Print("ok")
}
'''
    helper_go = Path("/tmp/make_blob.go")
    helper_bin = Path("/tmp/make_blob")
    helper_go.write_text(helper_source)
    subprocess.run(
        ["go", "build", "-o", str(helper_bin), str(helper_go)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )

    session_id = "8f9a2b3c4d5e6f7a"
    pin_number = 7392
    while pin_number == 7392:
        pin_number = 7000 + secrets.randbelow(3000)
    pin = f"{pin_number:04d}"
    plaintext = f"FLAG{{dynamic_{secrets.token_hex(24)}}}".encode()

    subprocess.run(
        [str(helper_bin), pin, session_id, "/home/user/exfiltrated.enc"],
        input=plaintext,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    recovered_path.unlink(missing_ok=True)
    result = subprocess.run(
        ["go", "run", str(script_path)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
    )
    assert result.returncode == 0, (
        "decrypt.go did not run successfully:\n" +
        result.stderr.decode(errors="replace")
    )
    assert recovered_path.is_file(), "decrypt.go did not create recovered.txt"
    assert recovered_path.read_bytes() == plaintext, (
        "decrypt.go did not recover the freshly generated AES-256-GCM plaintext"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
