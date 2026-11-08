#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import py_compile
import re
import shutil
import stat
import subprocess
import tempfile

CRACK_PY_PATH = "/home/user/crack.py"
PASSPHRASE_TXT_PATH = "/home/user/passphrase.txt"
DECRYPTED_KEY_PATH = "/home/user/decrypted_id_rsa"
DROPPER_PATH = "/home/user/evidence/dropper.elf"
ENCRYPTED_KEY_PATH = "/home/user/evidence/id_rsa"
EXPECTED_PASSPHRASE = "7492admin"


def derive_passphrase_from_rodata():
    result = subprocess.run(
        ["readelf", "-p", ".rodata", DROPPER_PATH],
        check=True,
        capture_output=True,
        text=True,
    )
    hashes = set(re.findall(r"(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])", result.stdout))
    matches = []
    for value in range(10000):
        candidate = f"{value:04d}admin"
        digest = hashlib.sha256(candidate.encode()).hexdigest()
        if any(digest == item.lower() for item in hashes):
            matches.append(candidate)
    assert len(matches) == 1, "Could not uniquely derive the passphrase from the SHA-256 hash in .rodata."
    return matches[0]


DERIVED_PASSPHRASE = derive_passphrase_from_rodata()


def public_key_from_private(path, passphrase):
    result = subprocess.run(
        ["ssh-keygen", "-y", "-P", passphrase, "-f", path],
        check=True,
        capture_output=True,
        text=True,
        timeout=15,
    )
    fields = result.stdout.strip().split()
    assert len(fields) >= 2, f"ssh-keygen did not produce a valid public key for {path}."
    return fields[0], fields[1]


def test_crack_script_exists():
    assert os.path.isfile(CRACK_PY_PATH), f"The script {CRACK_PY_PATH} is missing."


def test_crack_script_executes_and_recreates_passphrase():
    py_compile.compile(CRACK_PY_PATH, doraise=True)
    if os.path.lexists(PASSPHRASE_TXT_PATH):
        os.unlink(PASSPHRASE_TXT_PATH)
    subprocess.run(
        ["python3", CRACK_PY_PATH],
        cwd="/home/user",
        check=True,
        timeout=30,
    )
    assert os.path.isfile(PASSPHRASE_TXT_PATH), (
        f"Running {CRACK_PY_PATH} did not create {PASSPHRASE_TXT_PATH}."
    )


def test_passphrase_file():
    assert os.path.isfile(PASSPHRASE_TXT_PATH), f"The file {PASSPHRASE_TXT_PATH} is missing."
    with open(PASSPHRASE_TXT_PATH, "r") as f:
        content = f.read().strip()
    assert DERIVED_PASSPHRASE == EXPECTED_PASSPHRASE, "The supplied artifacts do not yield the expected passphrase."
    assert content == DERIVED_PASSPHRASE, f"The passphrase in {PASSPHRASE_TXT_PATH} is incorrect."
    assert content == EXPECTED_PASSPHRASE, f"The passphrase in {PASSPHRASE_TXT_PATH} is incorrect."


def test_decrypted_key_exists():
    assert os.path.isfile(DECRYPTED_KEY_PATH), f"The decrypted key file {DECRYPTED_KEY_PATH} is missing."


def test_decrypted_key_permissions():
    assert os.path.isfile(DECRYPTED_KEY_PATH), f"The decrypted key file {DECRYPTED_KEY_PATH} is missing."
    st = os.stat(DECRYPTED_KEY_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Permissions on {DECRYPTED_KEY_PATH} are {oct(perms)}, expected 0o600."


def test_decrypted_key_unencrypted():
    assert os.path.isfile(DECRYPTED_KEY_PATH), f"The decrypted key file {DECRYPTED_KEY_PATH} is missing."
    with open(DECRYPTED_KEY_PATH, "r") as f:
        content = f.read()
    assert "PRIVATE KEY" in content, f"The file {DECRYPTED_KEY_PATH} does not appear to be a private key."
    assert "ENCRYPTED" not in content, f"The file {DECRYPTED_KEY_PATH} is still encrypted."
    assert "-----BEGIN OPENSSH PRIVATE KEY-----" in content, (
        f"The file {DECRYPTED_KEY_PATH} does not contain a BEGIN OPENSSH PRIVATE KEY block."
    )


def test_decrypted_key_matches_encrypted_source():
    with tempfile.TemporaryDirectory() as tmpdir:
        encrypted_copy = os.path.join(tmpdir, "id_rsa")
        shutil.copyfile(ENCRYPTED_KEY_PATH, encrypted_copy)
        os.chmod(encrypted_copy, 0o600)
        encrypted_public = public_key_from_private(encrypted_copy, DERIVED_PASSPHRASE)

    decrypted_public = public_key_from_private(DECRYPTED_KEY_PATH, "")
    assert decrypted_public == encrypted_public, (
        f"{DECRYPTED_KEY_PATH} is not the decrypted form of {ENCRYPTED_KEY_PATH}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
