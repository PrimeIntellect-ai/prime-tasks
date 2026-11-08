#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import base64
import binascii
import secrets
import subprocess
import pytest
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

KEY_PATH = "/home/user/.secrets/new_aes.key"
SSH_KEY_PATH = "/home/user/.ssh/new_service_key"
LEGACY_PATH = "/home/user/data/legacy.enc"
OUTPUT_PATH = "/home/user/data/ips_secured.enc"
OLD_KEY = b"32-byte-old-insecure-key-1234567"


def read_new_key():
    with open(KEY_PATH, "r") as f:
        content = f.read().strip()
    return base64.b64decode(content, validate=True)


def decrypt_output():
    key = read_new_key()
    with open(OUTPUT_PATH, "rb") as f:
        encoded = f.read().strip()
    raw = binascii.unhexlify(encoded)
    assert len(raw) >= 12 + 16, "Encrypted output is too short for an AES-GCM payload."
    return AESGCM(key).decrypt(raw[:12], raw[12:], None).decode()


def write_legacy(plaintext):
    nonce = os.urandom(12)
    ciphertext = AESGCM(OLD_KEY).encrypt(nonce, plaintext.encode(), None)
    with open(LEGACY_PATH, "wb") as f:
        f.write(binascii.hexlify(nonce + ciphertext))


def random_ip():
    return ".".join(str(secrets.randbelow(254) + 1) for _ in range(4))


def make_dynamic_payload():
    ips = []
    while len(ips) < 4:
        candidate = random_ip()
        if candidate not in ips and candidate not in {
            "192.168.1.50", "10.0.0.5", "203.0.113.42"
        }:
            ips.append(candidate)
    plaintext = (
        f"boot marker={secrets.token_hex(8)} source {ips[0]} accepted; "
        f"peer {ips[1]} rejected; duplicate {ips[0]}; "
        f"route {ips[2]} active and destination {ips[3]} closed."
    )
    return plaintext, set(ips)


def assert_dynamic_output(expected):
    plaintext = decrypt_output().strip()
    values = [part.strip() for part in plaintext.split(",") if part.strip()]
    assert set(values) == expected, f"Dynamic payload produced incorrect IPs: {plaintext}"
    assert len(values) == len(expected), f"Dynamic payload contains duplicate IPs: {plaintext}"


def test_secrets_directory_and_key():
    assert os.path.isdir("/home/user/.secrets"), "/home/user/.secrets is missing."
    assert os.path.isfile(KEY_PATH), f"File {KEY_PATH} is missing."

    st = os.stat(KEY_PATH)
    assert stat.S_IMODE(st.st_mode) == 0o600, f"Permissions for {KEY_PATH} are not 0600."

    try:
        key_bytes = read_new_key()
        assert len(key_bytes) == 32, "Decoded AES key is not 32 bytes."
    except Exception as e:
        pytest.fail(f"Failed to base64 decode the AES key: {e}")


def test_ssh_key_permissions_and_passphrase():
    assert os.path.isfile(SSH_KEY_PATH), f"File {SSH_KEY_PATH} is missing."

    st = os.stat(SSH_KEY_PATH)
    assert stat.S_IMODE(st.st_mode) == 0o600, f"Permissions for {SSH_KEY_PATH} are not 0600."
    assert os.path.isfile(SSH_KEY_PATH + ".pub"), "SSH public key is missing."

    derived = subprocess.run(
        ["ssh-keygen", "-y", "-P", "rotated_pass_2024", "-f", SSH_KEY_PATH],
        capture_output=True, text=True, timeout=10
    )
    assert derived.returncode == 0, "SSH private key cannot be opened with the required passphrase."
    derived_fields = derived.stdout.strip().split()
    assert len(derived_fields) >= 2 and derived_fields[0] == "ssh-ed25519", \
        "SSH private key is not an Ed25519 key."

    with open(SSH_KEY_PATH + ".pub", "r") as f:
        public_fields = f.read().strip().split()
    assert len(public_fields) >= 2 and public_fields[0] == "ssh-ed25519", \
        "SSH public key is not an Ed25519 key."
    assert public_fields[:2] == derived_fields[:2], "SSH public and private keys do not match."

    wrong = subprocess.run(
        ["ssh-keygen", "-y", "-P", "definitely_not_rotated_pass_2024", "-f", SSH_KEY_PATH],
        capture_output=True, text=True, timeout=10
    )
    assert wrong.returncode != 0, "SSH private key is not protected by the required passphrase."


def test_go_and_shell_scripts_exist():
    assert os.path.isfile("/home/user/rotate.go"), "/home/user/rotate.go is missing."
    assert os.path.isfile("/home/user/run.sh"), "/home/user/run.sh is missing."

    with open("/home/user/run.sh", "r", errors="replace") as f:
        script = f.read()
    assert "32-byte-old-insecure-key-1234567" not in script, \
        "The old AES secret must not be passed by run.sh."
    assert "rotated_pass_2024" not in script, \
        "The SSH passphrase must not be passed by run.sh."
    with open(KEY_PATH, "r") as f:
        key_text = f.read().strip()
    assert key_text not in script, "The new AES key must not be passed by run.sh."


def test_encrypted_ips_payload():
    assert os.path.isfile(OUTPUT_PATH), f"File {OUTPUT_PATH} is missing."

    verifier_go = '''package main
import (
    "crypto/aes"
    "crypto/cipher"
    "encoding/base64"
    "encoding/hex"
    "fmt"
    "os"
    "strings"
)
func main() {
    keyB64, err := os.ReadFile("/home/user/.secrets/new_aes.key")
    if err != nil { os.Exit(1) }
    key, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(keyB64)))
    if err != nil { os.Exit(2) }

    encHex, err := os.ReadFile("/home/user/data/ips_secured.enc")
    if err != nil { os.Exit(3) }
    encBytes, err := hex.DecodeString(strings.TrimSpace(string(encHex)))
    if err != nil { os.Exit(4) }

    if len(encBytes) < 12 { os.Exit(5) }

    block, err := aes.NewCipher(key)
    if err != nil { os.Exit(6) }

    aesgcm, err := cipher.NewGCM(block)
    if err != nil { os.Exit(7) }

    nonce := encBytes[:12]
    ciphertext := encBytes[12:]

    plaintext, err := aesgcm.Open(nil, nonce, ciphertext, nil)
    if err != nil { os.Exit(8) }

    fmt.Print(string(plaintext))
}
'''
    verifier_path = "/tmp/verify_decryption.go"
    with open(verifier_path, "w") as f:
        f.write(verifier_go)

    result = subprocess.run(["go", "run", verifier_path], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to decrypt ips_secured.enc using the new AES key. Go exit code: {result.returncode}")

    plaintext = result.stdout.strip()
    expected_ips = {"192.168.1.50", "10.0.0.5", "203.0.113.42"}
    actual_ips = set(ip.strip() for ip in plaintext.split(","))
    assert actual_ips == expected_ips, f"Decrypted payload does not contain the correct IPs. Got: {plaintext}"


def test_rotate_go_and_run_script_process_dynamic_legacy_data():
    build = subprocess.run(
        ["go", "build", "-o", "/tmp/rotate_submission", "/home/user/rotate.go"],
        cwd="/home/user", capture_output=True, text=True, timeout=60
    )
    assert build.returncode == 0, f"rotate.go did not compile: {build.stderr}"

    plaintext, expected = make_dynamic_payload()
    write_legacy(plaintext)
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    direct = subprocess.run(
        ["/tmp/rotate_submission"], cwd="/home/user",
        capture_output=True, text=True, timeout=30
    )
    assert direct.returncode == 0, f"Compiled rotate.go failed: {direct.stderr}"
    assert os.path.isfile(OUTPUT_PATH), "rotate.go did not create ips_secured.enc."
    assert_dynamic_output(expected)

    plaintext, expected = make_dynamic_payload()
    write_legacy(plaintext)
    os.remove(OUTPUT_PATH)
    scripted = subprocess.run(
        ["bash", "/home/user/run.sh"], cwd="/home/user",
        capture_output=True, text=True, timeout=60
    )
    assert scripted.returncode == 0, f"run.sh failed: {scripted.stderr}"
    assert os.path.isfile(OUTPUT_PATH), "run.sh did not create ips_secured.enc."
    assert_dynamic_output(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
