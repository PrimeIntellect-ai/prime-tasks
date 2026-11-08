#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import textwrap


def regular_file(path):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f"{path} must be a regular file."
    return st


def test_auth_service_patched():
    filepath = "/home/user/app/auth_service_fixed.cpp"
    assert os.path.isfile(filepath), f"Patched file {filepath} does not exist."
    regular_file(filepath)

    with open(filepath, "r") as f:
        content = f.read()

    expected_query = 'std::string query = "SELECT * FROM users WHERE token = ?";'
    assert expected_query in content, "The vulnerable query was not replaced with the exact parameterized query string requested."
    assert "// Parameterized query" in content, "The comment '// Parameterized query' is missing."

    lines = content.splitlines()
    query_lines = [i for i, line in enumerate(lines) if expected_query in line]
    assert query_lines, "The exact parameterized query line is missing."
    assert any(i + 1 < len(lines) and lines[i + 1].strip() == "// Parameterized query" for i in query_lines), \
        "The comment '// Parameterized query' must be on the next line."

    assert "EVP_aes_256_cbc()" in content, "The cipher was not changed to EVP_aes_256_cbc()."
    assert "EVP_aes_256_ecb()" not in content, "The broken EVP_aes_256_ecb() cipher is still used."
    assert '"0000000000000000"' in content or "'0', '0'" in content or "0000000000000000" in content, \
        "The IV of 16 '0's was not found in the file."

    harness = r'''
#define main auth_service_submission_main
#include "/home/user/app/auth_service_fixed.cpp"
#undef main

#include <openssl/evp.h>
#include <openssl/rand.h>
#include <cstring>
#include <iostream>
#include <string>

static int reference_encrypt(const unsigned char *plaintext, int plaintext_len,
                             const unsigned char *key, unsigned char *ciphertext) {
    const unsigned char iv[16] = {
        '0','0','0','0','0','0','0','0',
        '0','0','0','0','0','0','0','0'
    };
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;
    int len = 0, total = 0;
    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), nullptr, key, iv) != 1 ||
        EVP_EncryptUpdate(ctx, ciphertext, &len, plaintext, plaintext_len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }
    total = len;
    if (EVP_EncryptFinal_ex(ctx, ciphertext + total, &len) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }
    total += len;
    EVP_CIPHER_CTX_free(ctx);
    return total;
}

int main() {
    const std::string tokens[] = {
        "ordinary-token",
        "' OR 1=1 --",
        "x'; DROP TABLE users; --"
    };
    for (const auto &token : tokens) {
        if (getUserByToken(token) != "SELECT * FROM users WHERE token = ?") {
            std::cerr << "getUserByToken did not return the parameterized query";
            return 10;
        }
    }

    unsigned char key[32];
    unsigned char plaintext[64];
    if (RAND_bytes(key, sizeof(key)) != 1 || RAND_bytes(plaintext, sizeof(plaintext)) != 1)
        return 11;

    const int lengths[] = {1, 16, 31, 47};
    for (int plaintext_len : lengths) {
        unsigned char actual[128];
        unsigned char expected[128];
        std::memset(actual, 0xA5, sizeof(actual));
        std::memset(expected, 0, sizeof(expected));
        encryptData(plaintext, plaintext_len, key, actual);
        int expected_len = reference_encrypt(plaintext, plaintext_len, key, expected);
        if (expected_len < 0 || std::memcmp(actual, expected, expected_len) != 0) {
            std::cerr << "encryptData is not AES-256-CBC with the required hardcoded IV";
            return 12;
        }
        if (RAND_bytes(key, sizeof(key)) != 1 || RAND_bytes(plaintext, sizeof(plaintext)) != 1)
            return 13;
    }
    return 0;
}
'''

    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "harness.cpp")
        binary_path = os.path.join(td, "auth_test")
        with open(harness_path, "w") as f:
            f.write(harness)
        build = subprocess.run(
            ["g++", "-std=c++17", harness_path, "-lcrypto", "-o", binary_path],
            capture_output=True, text=True, timeout=30
        )
        assert build.returncode == 0, f"Patched C++ source does not compile:\n{build.stdout}\n{build.stderr}"
        run = subprocess.run([binary_path], capture_output=True, text=True, timeout=10)
        assert run.returncode == 0, f"Patched C++ behavior is incorrect: {run.stdout}{run.stderr}"


def test_credential_rotation():
    rotated_file = "/home/user/secrets/db_config_rotated.enc"
    assert os.path.isfile(rotated_file), f"Rotated credentials file {rotated_file} does not exist."
    regular_file(rotated_file)

    new_key = "6e65775f7365637265745f6b65795f31323334353637383930313233343536"
    new_iv = "30303030303030303030303030303030"
    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc",
        "-K", new_key, "-iv", new_iv, "-in", rotated_file
    ]
    result = subprocess.run(cmd, capture_output=True)
    assert result.returncode == 0, f"Failed to decrypt {rotated_file} with the new AES-256-CBC key and IV. OpenSSL error: {result.stderr.decode()}"
    plaintext = result.stdout.decode().strip()
    assert plaintext == "DB_PASS=SuperSecretPassword123!", f"Decrypted content does not match the expected plaintext. Got: {plaintext}"


def test_ssh_hardening():
    ssh_dir = "/home/user/.ssh"
    priv_key_path = os.path.join(ssh_dir, "deploy_key")
    pub_key_path = os.path.join(ssh_dir, "deploy_key.pub")
    auth_keys_path = os.path.join(ssh_dir, "authorized_keys")

    assert os.path.isfile(priv_key_path), f"Private key file {priv_key_path} does not exist."
    assert os.path.isfile(pub_key_path), f"Public key file {pub_key_path} does not exist."
    assert os.path.isfile(auth_keys_path), f"Authorized keys file {auth_keys_path} does not exist."

    ssh_st = os.lstat(ssh_dir)
    assert stat.S_ISDIR(ssh_st.st_mode), f"{ssh_dir} must be a directory."
    assert stat.S_IMODE(ssh_st.st_mode) == 0o700, f"{ssh_dir} must have permissions 700."
    assert stat.S_IMODE(regular_file(priv_key_path).st_mode) == 0o600, f"{priv_key_path} must have permissions 600."
    assert stat.S_IMODE(regular_file(pub_key_path).st_mode) == 0o644, f"{pub_key_path} must have permissions 644."
    assert stat.S_IMODE(regular_file(auth_keys_path).st_mode) == 0o600, f"{auth_keys_path} must have permissions 600."

    derived = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", priv_key_path],
        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10
    )
    assert derived.returncode == 0, f"deploy_key is not a valid unencrypted SSH private key: {derived.stderr}"
    derived_parts = derived.stdout.strip().split()
    assert len(derived_parts) >= 2 and derived_parts[0] == "ssh-ed25519", "deploy_key is not an Ed25519 private key."
    derived_identity = derived_parts[:2]

    with open(pub_key_path, "r") as f:
        pub_parts = f.read().strip().split()
    assert len(pub_parts) >= 2 and pub_parts[0] == "ssh-ed25519", "deploy_key.pub is not valid Ed25519 public-key text."
    assert pub_parts[:2] == derived_identity, "deploy_key.pub does not correspond to deploy_key."

    with open(auth_keys_path, "r") as f:
        auth_keys = f.read().strip().splitlines()

    expected_prefix = 'command="/opt/deploy.sh",no-pty,no-port-forwarding ssh-ed25519 '
    candidates = [line for line in auth_keys if line.startswith(expected_prefix)]
    assert candidates, f"Could not find an entry in {auth_keys_path} starting exactly with '{expected_prefix}'."

    matching_line = None
    for line in candidates:
        key_text = line[len('command="/opt/deploy.sh",no-pty,no-port-forwarding '):]
        parts = key_text.split()
        if len(parts) >= 2 and parts[:2] == derived_identity:
            matching_line = line
            break
    assert matching_line is not None, "The hardened authorized_keys entry does not contain the public key corresponding to deploy_key."

    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(" ".join(derived_identity) + "\n")
        validation_path = f.name
    try:
        validation = subprocess.run(
            ["ssh-keygen", "-l", "-f", validation_path],
            capture_output=True, text=True, timeout=10
        )
        assert validation.returncode == 0 and "ED25519" in validation.stdout.upper(), \
            f"The authorized Ed25519 public key is syntactically invalid: {validation.stderr}"
    finally:
        os.unlink(validation_path)


def test_certificate_chain_validation():
    status_file = "/home/user/cert_status.txt"
    assert os.path.isfile(status_file), f"Certificate status file {status_file} does not exist."
    regular_file(status_file)

    with open(status_file, "r") as f:
        status = f.read().strip()
    assert status == "VALID", f"Expected cert_status.txt to contain exactly 'VALID', but got '{status}'."

    verify = subprocess.run(
        ["openssl", "verify", "-CAfile", "/home/user/certs/root.crt",
         "-untrusted", "/home/user/certs/intermediate.crt",
         "/home/user/certs/server.crt"],
        capture_output=True, text=True, timeout=15
    )
    assert verify.returncode == 0, \
        f"OpenSSL does not validate server.crt through the provided intermediate and root certificates: {verify.stdout}{verify.stderr}"
    assert "/home/user/certs/server.crt: OK" in verify.stdout, \
        f"OpenSSL did not report the server certificate chain as valid: {verify.stdout}{verify.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
