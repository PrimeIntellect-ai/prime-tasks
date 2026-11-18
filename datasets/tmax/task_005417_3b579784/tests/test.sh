#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import os
import secrets
import stat
import subprocess

COMPROMISED_KEY_1 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCcompromised1 dummy@host"
COMPROMISED_KEY_2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIcompromised2 dummy@host"
SAFE_KEY_1 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsafe1 alice@host"
SAFE_KEY_2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIsafe2 bob@host"


def assert_genuine_ed25519_pair(priv_key_path, pub_key_path):
    result = subprocess.run(
        ["ssh-keygen", "-y", "-f", priv_key_path],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Private key is not readable by ssh-keygen: {result.stderr}"

    derived_parts = result.stdout.strip().split()
    with open(pub_key_path, "r") as f:
        public_lines = [line.strip() for line in f if line.strip()]

    assert len(public_lines) == 1, "Public key file must contain exactly one non-empty key line."
    public_parts = public_lines[0].split()
    assert len(derived_parts) >= 2 and len(public_parts) >= 2, "Malformed SSH public key."
    assert derived_parts[:2] == public_parts[:2], "Public key does not match the private key."
    assert public_parts[0] == "ssh-ed25519", "Generated key is not Ed25519."

    blob = base64.b64decode(public_parts[1], validate=True)
    name_len = int.from_bytes(blob[0:4], "big")
    name = blob[4:4 + name_len]
    offset = 4 + name_len
    key_len = int.from_bytes(blob[offset:offset + 4], "big")
    key = blob[offset + 4:offset + 4 + key_len]
    assert name == b"ssh-ed25519" and key_len == 32 and len(key) == 32, "Invalid Ed25519 public key blob."


def test_rotation_report():
    report_path = "/home/user/rotation_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        content = f.read()

    assert "Removed compromised keys: 4" in content, "Report does not contain the correct count of removed keys (expected 4)."
    assert "Admin key generated: true" in content, "Report does not contain 'Admin key generated: true'."


def test_admin_key_permissions():
    priv_key_path = "/home/user/app_users/admin/id_ed25519"
    pub_key_path = "/home/user/app_users/admin/id_ed25519.pub"

    assert os.path.isfile(priv_key_path), f"Admin private key {priv_key_path} does not exist."
    assert os.path.isfile(pub_key_path), f"Admin public key {pub_key_path} does not exist."

    priv_mode = stat.S_IMODE(os.stat(priv_key_path).st_mode)
    pub_mode = stat.S_IMODE(os.stat(pub_key_path).st_mode)

    assert priv_mode == 0o600, f"Private key permissions should be 0600, got {oct(priv_mode)}."
    assert pub_mode == 0o644, f"Public key permissions should be 0644, got {oct(pub_mode)}."


def test_alice_authorized_keys_sanitized():
    filepath = "/home/user/app_users/alice/authorized_keys"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read().splitlines()

    assert SAFE_KEY_1 in content, f"Alice's safe key was removed from {filepath}."
    assert COMPROMISED_KEY_1 not in content, f"Compromised key 1 still present in {filepath}."
    assert COMPROMISED_KEY_2 not in content, f"Compromised key 2 still present in {filepath}."


def test_bob_authorized_keys_sanitized():
    filepath = "/home/user/app_users/bob/authorized_keys"
    assert os.path.isfile(filepath), f"File {filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read().splitlines()

    assert SAFE_KEY_2 in content, f"Bob's safe key was removed from {filepath}."
    assert COMPROMISED_KEY_2 not in content, f"Compromised key 2 still present in {filepath}."


def test_admin_authorized_keys_updated():
    filepath = "/home/user/app_users/admin/authorized_keys"
    pub_key_path = "/home/user/app_users/admin/id_ed25519.pub"

    assert os.path.isfile(filepath), f"File {filepath} does not exist."
    assert os.path.isfile(pub_key_path), f"Admin public key {pub_key_path} does not exist."

    with open(filepath, "r") as f:
        auth_content = f.read().splitlines()

    with open(pub_key_path, "r") as f:
        pub_content = f.read().strip()

    assert COMPROMISED_KEY_1 not in auth_content, f"Compromised key 1 still present in {filepath}."
    assert pub_content in auth_content, f"Newly generated admin public key was not appended to {filepath}."


def test_generated_files_are_a_real_ed25519_pair():
    assert_genuine_ed25519_pair(
        "/home/user/app_users/admin/id_ed25519",
        "/home/user/app_users/admin/id_ed25519.pub",
    )


def test_z_program_executes_on_runtime_generated_inputs():
    source = "/home/user/rotator.go"
    assert os.path.isfile(source), f"Required Go program {source} does not exist."
    assert stat.S_ISREG(os.stat(source).st_mode), f"{source} is not a regular file."

    token = secrets.token_hex(16)
    compromised_a = f"ssh-ed25519 RUNTIME_{token}_A compromised@test"
    compromised_b = f"ssh-rsa RUNTIME_{token}_B compromised@test"
    safe_line = f"ssh-ed25519 RUNTIME_{token}_SAFE safe@test"

    runtime_dir = f"/home/user/app_users/runtime_{token}"
    os.mkdir(runtime_dir)
    runtime_auth = os.path.join(runtime_dir, "authorized_keys")
    with open(runtime_auth, "w") as f:
        f.write(safe_line + "\n")
        f.write(compromised_a + "\n")
        f.write(compromised_a + "\n")
        f.write(compromised_b + "\n")

    alice_auth = "/home/user/app_users/alice/authorized_keys"
    with open(alice_auth, "a") as f:
        f.write(compromised_b + "\n")

    with open("/home/user/compromised.list", "w") as f:
        f.write(compromised_a + "\n")
        f.write(compromised_b + "\n")

    compromised = {compromised_a, compromised_b}
    before = {}
    for path in glob.glob("/home/user/app_users/*/authorized_keys"):
        with open(path, "r") as f:
            before[path] = f.read().splitlines()
    expected_removed = sum(line in compromised for lines in before.values() for line in lines)
    assert expected_removed == 4

    priv = "/home/user/app_users/admin/id_ed25519"
    pub = "/home/user/app_users/admin/id_ed25519.pub"
    for path in (priv, pub):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["go", "run", source],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Go program failed on fresh inputs:\nstdout: {result.stdout}\nstderr: {result.stderr}"

    for path, old_lines in before.items():
        assert os.path.isfile(path), f"Program removed {path}."
        with open(path, "r") as f:
            new_lines = f.read().splitlines()
        expected = [line for line in old_lines if line not in compromised]
        if path.endswith("/admin/authorized_keys"):
            with open(pub, "r") as f:
                expected.append(f.read().strip())
        assert new_lines == expected, f"Incorrect sanitization result for {path}."

    with open(runtime_auth, "r") as f:
        assert f.read().splitlines() == [safe_line]

    assert stat.S_IMODE(os.stat(priv).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(pub).st_mode) == 0o644
    assert_genuine_ed25519_pair(priv, pub)

    with open("/home/user/rotation_report.txt", "r") as f:
        report_lines = f.read().splitlines()
    assert report_lines == [
        f"Removed compromised keys: {expected_removed}",
        "Admin key generated: true",
    ]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
