#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_malicious_ips_file():
    ips_path = "/home/user/malicious_ips.txt"
    assert os.path.isfile(ips_path), f"File missing: {ips_path}"

    with open(ips_path, "r") as f:
        ips = [line.strip() for line in f if line.strip()]

    expected_ips = ["10.0.0.5", "203.0.113.42"]
    assert ips == expected_ips, f"Expected IPs {expected_ips}, but got {ips} in {ips_path}"

def test_block_rules_file():
    rules_path = "/home/user/block_rules.ipv4"
    assert os.path.isfile(rules_path), f"File missing: {rules_path}"

    with open(rules_path, "r") as f:
        rules = [line.strip() for line in f if line.strip()]

    expected_rules = [
        "-A INPUT -s 10.0.0.5 -j DROP",
        "-A INPUT -s 203.0.113.42 -j DROP"
    ]
    assert rules == expected_rules, f"Expected rules {expected_rules}, but got {rules} in {rules_path}"

def test_clean_uploads():
    clean_dir = "/home/user/clean_uploads"
    assert os.path.isdir(clean_dir), f"Directory missing: {clean_dir}"

    expected_files = {
        "file1.txt": "This is a clean file.\nIt has no malicious payloads.\n",
        "file4.txt": "Another clean file from this IP.\n"
    }

    for filename, expected_content in expected_files.items():
        file_path = os.path.join(clean_dir, filename)
        assert os.path.isfile(file_path), f"Clean file missing: {file_path}"
        with open(file_path, "r") as f:
            content = f.read()
        assert content == expected_content, f"Content mismatch in {file_path}"

def test_secure_vault_encryption():
    vault_dir = "/home/user/secure_vault"
    assert os.path.isdir(vault_dir), f"Directory missing: {vault_dir}"

    enc_file = os.path.join(vault_dir, "file3.txt.enc")
    assert os.path.isfile(enc_file), f"Encrypted file missing: {enc_file}"

    # Decrypt the file to verify
    decrypted_file = "/tmp/file3.txt.dec"
    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-pass", "pass:DevSecOps2024!",
        "-in", enc_file,
        "-out", decrypted_file
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Decryption failed: {result.stderr}"

    assert os.path.isfile(decrypted_file), "Decrypted file was not created"

    with open(decrypted_file, "r") as f:
        content = f.read()

    expected_content = "Here is my payment info.\nMy card is 1234567812345678.\nThanks!\n"
    assert content == expected_content, "Decrypted content does not match original"

    # Cleanup
    os.remove(decrypted_file)

def test_quarantine_is_empty():
    quarantine_dir = "/home/user/quarantine"
    assert os.path.isdir(quarantine_dir), f"Directory missing: {quarantine_dir}"

    files = os.listdir(quarantine_dir)
    assert len(files) == 0, f"Quarantine directory is not empty, found: {files}"
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_general_processing.py
import os
import secrets
import subprocess

SCRIPT = "/home/user/enforce_policy.sh"
HOME = "/home/user"
QUARANTINE = os.path.join(HOME, "quarantine")
LOG = os.path.join(HOME, "upload_log.csv")

assert os.path.isfile(SCRIPT), f"Required script missing: {SCRIPT}"
assert os.access(SCRIPT, os.X_OK), f"Required script is not executable: {SCRIPT}"
with open(SCRIPT, "rb") as f:
    first_line = f.readline().decode("utf-8", "replace").strip()
assert first_line.startswith("#!") and "bash" in first_line, "Script must have a Bash shebang"

token = secrets.token_hex(8)
clean_name = f"verify_{token}_clean.txt"
card_name = f"verify_{token}_card.txt"
malicious_names = [f"verify_{token}_malicious_{i}.txt" for i in range(6)]

clean_content = f"Dynamically generated clean upload {token}.\n"
card_number = "4" + "".join(str(secrets.randbelow(10)) for _ in range(15))
card_content = f"Dynamic payment record {token}: {card_number}\n"
malicious_contents = [
    "dynamic traversal ../etc/hosts\n",
    "dynamic traversal ..%2fetc%2fhosts\n",
    "dynamic traversal %2e%2e%2fetc%2fhosts\n",
    "dynamic traversal %2e%2e/etc/hosts\n",
    "dynamic traversal ..\\windows\\system.ini\n",
    f"malicious takes precedence ../private and card {card_number}\n",
]
malicious_ips = [
    "198.51.100.77",
    "8.8.8.8",
    "198.51.100.77",
    "8.8.8.8",
    "198.51.100.77",
    "8.8.8.8",
]

for name, content in [(clean_name, clean_content), (card_name, card_content)]:
    with open(os.path.join(QUARANTINE, name), "w") as f:
        f.write(content)
for name, content in zip(malicious_names, malicious_contents):
    with open(os.path.join(QUARANTINE, name), "w") as f:
        f.write(content)

with open(LOG, "a") as f:
    f.write(f"{clean_name},192.0.2.21,1777777700\n")
    f.write(f"{card_name},192.0.2.22,1777777701\n")
    for i, (name, ip) in enumerate(zip(malicious_names, malicious_ips), start=2):
        f.write(f"{name},{ip},{1777777700 + i}\n")

result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=30)
assert result.returncode == 0, (
    f"Script failed with status {result.returncode}\nstdout: {result.stdout}\nstderr: {result.stderr}"
)

assert os.listdir(QUARANTINE) == [], "Script did not process every dynamic quarantine file"

clean_path = os.path.join(HOME, "clean_uploads", clean_name)
assert os.path.isfile(clean_path), "Dynamic clean file was not moved to clean_uploads"
with open(clean_path) as f:
    assert f.read() == clean_content, "Dynamic clean file content changed"

enc_path = os.path.join(HOME, "secure_vault", card_name + ".enc")
assert os.path.isfile(enc_path), "Dynamic card-containing file was not encrypted"
decrypted_path = f"/tmp/{card_name}.dec"
dec = subprocess.run([
    "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
    "-pass", "pass:DevSecOps2024!", "-in", enc_path, "-out", decrypted_path
], capture_output=True, text=True)
assert dec.returncode == 0, f"Dynamic encrypted file could not be decrypted: {dec.stderr}"
with open(decrypted_path) as f:
    assert f.read() == card_content, "Dynamic decrypted content does not match its input"
os.remove(decrypted_path)

for name in malicious_names:
    assert not os.path.exists(os.path.join(QUARANTINE, name)), f"Malicious file was not deleted: {name}"
    assert not os.path.exists(os.path.join(HOME, "clean_uploads", name)), f"Malicious file was treated as clean: {name}"
    assert not os.path.exists(os.path.join(HOME, "secure_vault", name + ".enc")), f"Malicious file was encrypted instead of deleted: {name}"

expected_ips = sorted({"10.0.0.5", "203.0.113.42", *malicious_ips})
with open(os.path.join(HOME, "malicious_ips.txt")) as f:
    actual_ips = [line.strip() for line in f if line.strip()]
assert actual_ips == expected_ips, f"Expected sorted unique IPs {expected_ips}, got {actual_ips}"

expected_rules = [f"-A INPUT -s {ip} -j DROP" for ip in expected_ips]
with open(os.path.join(HOME, "block_rules.ipv4")) as f:
    actual_rules = [line.strip() for line in f if line.strip()]
assert actual_rules == expected_rules, f"Expected rules {expected_rules}, got {actual_rules}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_general_processing.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
