#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import stat
import subprocess
import tempfile
import pytest

LOG_PATH = "/home/user/auth_audit.log"
CRACKED_PATH = "/home/user/cracked.txt"
SOURCE_PATH = "/home/user/crack.cpp"
LEGACY_STORE = "/home/user/legacy_store.p12"
NEW_STORE = "/home/user/new_store.p12"
NEW_PASSWORD = "RotatedSecure123!"


def recovered_password():
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        log = f.read()
    match = re.search(r"user=sys_backup\s+hash=([0-9a-fA-F]{64})\b", log)
    assert match, "Could not find the sys_backup SHA-256 hash in auth_audit.log."
    target = match.group(1).lower()
    for number in range(10000):
        candidate = f"{number:04d}_backup"
        if hashlib.sha256(candidate.encode()).hexdigest() == target:
            return candidate, target
    pytest.fail("No password matching the stated legacy policy matches the audit hash.")


def run_checked(cmd):
    return subprocess.run(cmd, capture_output=True, check=True, timeout=30)


def test_cracked_txt_content():
    """Verify that cracked.txt contains the correct plaintext password."""
    assert os.path.isfile(CRACKED_PATH), f"File {CRACKED_PATH} does not exist."
    with open(CRACKED_PATH, "r") as f:
        content = f.read().strip()
    expected, _ = recovered_password()
    assert content == "7391_backup", f"Expected password '7391_backup', but found '{content}' in {CRACKED_PATH}."
    assert content == expected, "cracked.txt does not match the password derived from the audit hash."


def test_cracker_source_compiles_uses_openssl_and_runs():
    assert os.path.isfile(SOURCE_PATH), f"File {SOURCE_PATH} does not exist."
    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]openssl/sha\.h[>\"]", source), \
        "crack.cpp must include <openssl/sha.h>."
    assert re.search(r"\bSHA256(?:_Init|_Update|_Final)?\s*\(", source), \
        "crack.cpp must use OpenSSL's SHA-256 API."

    executable = "/tmp/submitted_cracker"
    compile_result = subprocess.run(
        ["g++", SOURCE_PATH, "-o", executable, "-lcrypto"],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"crack.cpp failed to compile with -lcrypto:\n{compile_result.stderr}"

    expected, target_hash = recovered_password()
    original = None
    original_mode = None
    if os.path.isfile(CRACKED_PATH):
        with open(CRACKED_PATH, "rb") as f:
            original = f.read()
        original_mode = stat.S_IMODE(os.stat(CRACKED_PATH).st_mode)
        os.unlink(CRACKED_PATH)

    generated = ""
    try:
        result = subprocess.run(
            [executable, target_hash], cwd="/home/user", input=target_hash + "\n",
            capture_output=True, text=True, timeout=30
        )
        if os.path.isfile(CRACKED_PATH):
            with open(CRACKED_PATH, "r", encoding="utf-8", errors="replace") as f:
                generated = f.read()
        combined = result.stdout + "\n" + result.stderr + "\n" + generated
        assert result.returncode == 0, f"Compiled cracker exited with status {result.returncode}:\n{result.stderr}"
        assert expected in combined, \
            "Running the compiled cracker did not output or create cracked.txt containing the recovered password."
    finally:
        if os.path.exists(CRACKED_PATH):
            os.unlink(CRACKED_PATH)
        if original is not None:
            with open(CRACKED_PATH, "wb") as f:
                f.write(original)
            os.chmod(CRACKED_PATH, original_mode)


def test_new_store_exists_and_permissions():
    """Verify that new_store.p12 exists and has strict 600 permissions."""
    assert os.path.isfile(NEW_STORE), f"File {NEW_STORE} does not exist."
    mode = stat.S_IMODE(os.stat(NEW_STORE).st_mode)
    assert mode == 0o600, f"Expected permissions 600 for {NEW_STORE}, but got {oct(mode)}."


def test_new_store_validity_and_password():
    """Verify that new_store.p12 is valid and protected with the new password."""
    cmd = [
        "openssl", "pkcs12", "-info", "-in", NEW_STORE,
        "-passin", f"pass:{NEW_PASSWORD}", "-noout"
    ]
    try:
        subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=30)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read {NEW_STORE} with the new password '{NEW_PASSWORD}'. OpenSSL error: {e.stderr}")


def test_new_store_preserves_original_certificate_and_private_key():
    """Compare normalized certificate and private-key material from both stores."""
    legacy_password, _ = recovered_password()
    with tempfile.TemporaryDirectory() as directory:
        legacy_cert = os.path.join(directory, "legacy-cert.pem")
        legacy_key = os.path.join(directory, "legacy-key.pem")
        new_cert = os.path.join(directory, "new-cert.pem")
        new_key = os.path.join(directory, "new-key.pem")

        try:
            run_checked(["openssl", "pkcs12", "-in", LEGACY_STORE,
                         "-passin", f"pass:{legacy_password}", "-clcerts", "-nokeys",
                         "-out", legacy_cert])
            run_checked(["openssl", "pkcs12", "-in", LEGACY_STORE,
                         "-passin", f"pass:{legacy_password}", "-nocerts", "-nodes",
                         "-out", legacy_key])
            run_checked(["openssl", "pkcs12", "-in", NEW_STORE,
                         "-passin", f"pass:{NEW_PASSWORD}", "-clcerts", "-nokeys",
                         "-out", new_cert])
            run_checked(["openssl", "pkcs12", "-in", NEW_STORE,
                         "-passin", f"pass:{NEW_PASSWORD}", "-nocerts", "-nodes",
                         "-out", new_key])

            legacy_cert_der = run_checked(["openssl", "x509", "-in", legacy_cert, "-outform", "DER"]).stdout
            new_cert_der = run_checked(["openssl", "x509", "-in", new_cert, "-outform", "DER"]).stdout
            legacy_key_der = run_checked(["openssl", "pkey", "-in", legacy_key, "-outform", "DER"]).stdout
            new_key_der = run_checked(["openssl", "pkey", "-in", new_key, "-outform", "DER"]).stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Could not extract and compare PKCS#12 contents: {e.stderr.decode(errors='replace')}")

        assert new_cert_der == legacy_cert_der, "The certificate in new_store.p12 differs from the legacy certificate."
        assert new_key_der == legacy_key_der, "The private key in new_store.p12 differs from the legacy private key."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
