#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import stat
import subprocess

WEB_CERTS_DIR = "/home/user/web_certs"
SERVER_KEY = os.path.join(WEB_CERTS_DIR, "server.key")
SERVER_CRT = os.path.join(WEB_CERTS_DIR, "server.crt")
AUDIT_REPORT = "/home/user/audit_report.txt"


def openssl_modulus(path, kind):
    proc = subprocess.run(
        ["openssl", kind, "-noout", "-modulus", "-in", path],
        capture_output=True,
    )
    assert proc.returncode == 0, f"Failed to get RSA modulus from {path}."
    return proc.stdout


def test_enc_files_deleted():
    assert not os.path.exists(os.path.join(WEB_CERTS_DIR, "backup_alpha.enc")), \
        "backup_alpha.enc should have been deleted."
    assert not os.path.exists(os.path.join(WEB_CERTS_DIR, "backup_beta.enc")), \
        "backup_beta.enc should have been deleted."


def test_server_key_exists_and_perms():
    assert os.path.isfile(SERVER_KEY), f"{SERVER_KEY} should exist."
    assert stat.S_IMODE(os.stat(SERVER_KEY).st_mode) == 0o600, \
        f"{SERVER_KEY} should have 600 permissions."


def test_server_crt_exists_and_perms():
    assert os.path.isfile(SERVER_CRT), f"{SERVER_CRT} should exist."
    assert stat.S_IMODE(os.stat(SERVER_CRT).st_mode) == 0o644, \
        f"{SERVER_CRT} should have 644 permissions."


def test_all_key_files_have_strict_permissions():
    for name in os.listdir(WEB_CERTS_DIR):
        path = os.path.join(WEB_CERTS_DIR, name)
        if name.endswith(".key"):
            assert stat.S_IMODE(os.stat(path).st_mode) == 0o600, \
                f"{path} should have 600 permissions."


def test_key_matches_cert_and_no_decoy_key_remains():
    key_mod = openssl_modulus(SERVER_KEY, "rsa").strip()
    cert_mod = openssl_modulus(SERVER_CRT, "x509").strip()
    assert key_mod == cert_mod, \
        "The RSA modulus of server.key does not match server.crt."

    # A matching decrypted temporary key may legitimately remain, but the
    # non-matching decrypted RSA key must have been deleted.
    for name in os.listdir(WEB_CERTS_DIR):
        path = os.path.join(WEB_CERTS_DIR, name)
        if path in (SERVER_KEY, SERVER_CRT) or not os.path.isfile(path):
            continue
        proc = subprocess.run(
            ["openssl", "rsa", "-noout", "-modulus", "-in", path],
            capture_output=True,
        )
        if proc.returncode == 0:
            assert proc.stdout.strip() == cert_mod, \
                f"A non-matching decrypted RSA key remains at {path}."


def acceptable_modulus_md5s(modulus_output):
    stripped = modulus_output.strip()
    modulus_hex = stripped.split(b"=", 1)[1] if b"=" in stripped else stripped

    representations = {
        modulus_output,
        stripped,
        stripped + b"\n",
        modulus_hex,
        modulus_hex + b"\n",
        modulus_hex.lower(),
        modulus_hex.lower() + b"\n",
    }

    try:
        raw = bytes.fromhex(modulus_hex.decode("ascii"))
        representations.add(raw)
        representations.add(b"\x00" + raw)  # ASN.1 positive-integer padding
        decimal = str(int(modulus_hex, 16)).encode("ascii")
        representations.add(decimal)
        representations.add(decimal + b"\n")
    except (ValueError, UnicodeDecodeError):
        pass

    return {hashlib.md5(value).hexdigest() for value in representations}


def test_audit_report_format():
    assert os.path.isfile(AUDIT_REPORT), f"{AUDIT_REPORT} should exist."

    with open(SERVER_KEY, "rb") as f:
        key_sha256 = hashlib.sha256(f.read()).hexdigest()

    key_modulus_output = openssl_modulus(SERVER_KEY, "rsa")

    entries = sorted(
        os.path.join(WEB_CERTS_DIR, name)
        for name in os.listdir(WEB_CERTS_DIR)
    )
    expected_stat_lines = []
    for path in entries:
        proc = subprocess.run(
            ["stat", "-c", "%n %a", path],
            capture_output=True,
            text=True,
        )
        assert proc.returncode == 0, f"Could not stat {path}."
        expected_stat_lines.append(proc.stdout.rstrip("\n"))

    with open(AUDIT_REPORT, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2 + len(expected_stat_lines), \
        "Audit report must contain two hash lines followed by every current directory entry."
    assert lines[0] == f"MATCHED KEY SHA256: {key_sha256}", \
        "Line 1 does not match the expected SHA256 format or value."

    prefix = "MODULUS MD5: "
    assert lines[1].startswith(prefix), "Line 2 does not match the expected MD5 format."
    supplied_md5 = lines[1][len(prefix):]
    assert supplied_md5 in acceptable_modulus_md5s(key_modulus_output), \
        "Line 2 is not a valid MD5 hash of a conventional RSA modulus representation."

    assert lines[2:] == expected_stat_lines, \
        "Report file listings must exactly match stat output sorted by absolute path."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
