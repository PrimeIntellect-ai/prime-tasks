#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import os
import re
import secrets
import string
import subprocess

import pytest

HOME = "/home/user"
CERT_DIR = os.path.join(HOME, "certs")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, check=True, **kwargs)


def assert_certificate(crt_path, key_path):
    assert os.path.isfile(crt_path), f"New certificate missing at {crt_path}"
    assert os.path.isfile(key_path), f"New private key missing at {key_path}"

    try:
        subject_output = run([
            "openssl", "x509", "-in", crt_path, "-noout", "-subject"
        ]).stdout.strip()
        assert "CN = secure.local" in subject_output or "CN=secure.local" in subject_output, \
            f"Certificate Common Name is incorrect. Expected 'secure.local', got: {subject_output}"

        subject = run([
            "openssl", "x509", "-in", crt_path, "-noout", "-subject", "-nameopt", "RFC2253"
        ]).stdout.strip().split("=", 1)[1]
        issuer = run([
            "openssl", "x509", "-in", crt_path, "-noout", "-issuer", "-nameopt", "RFC2253"
        ]).stdout.strip().split("=", 1)[1]
        assert subject == issuer, "Certificate is not self-signed (subject and issuer differ)"
        assert re.search(r"(?:^|,)CN=secure\.local(?:,|$)", subject), \
            f"Certificate CN is not exactly secure.local: {subject}"

        rsa_text = run(["openssl", "rsa", "-in", key_path, "-text", "-noout"]).stdout
        assert re.search(r"Private-Key: \(2048 bit(?:,|\))", rsa_text), \
            "Private key is not RSA-2048"
        run(["openssl", "rsa", "-in", key_path, "-check", "-noout"])

        cert_pub = subprocess.run(
            ["openssl", "x509", "-in", crt_path, "-pubkey", "-noout"],
            capture_output=True, check=True
        ).stdout
        cert_pub_der = subprocess.run(
            ["openssl", "pkey", "-pubin", "-outform", "DER"],
            input=cert_pub, capture_output=True, check=True
        ).stdout
        key_pub_der = subprocess.run(
            ["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"],
            capture_output=True, check=True
        ).stdout
        assert cert_pub_der == key_pub_der, "new.key does not match new.crt"

        run(["openssl", "verify", "-CAfile", crt_path, crt_path])

        dates = run([
            "openssl", "x509", "-in", crt_path, "-noout", "-startdate", "-enddate"
        ]).stdout.splitlines()
        not_before = datetime.datetime.strptime(dates[0].split("=", 1)[1], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=datetime.timezone.utc)
        not_after = datetime.datetime.strptime(dates[1].split("=", 1)[1], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=datetime.timezone.utc)
        duration = (not_after - not_before).total_seconds()
        assert abs(duration - 365 * 86400) <= 300, \
            f"Certificate validity is not 365 days: {duration / 86400:.3f} days"
        now = datetime.datetime.now(datetime.timezone.utc)
        assert not_before <= now <= not_after, "New certificate is not currently valid"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to validate certificate with openssl: {e.stderr}")


def test_audit_report_content():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"Audit report missing at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {report_path}, found {len(lines)}"
    assert lines[0] == "CRACKED_PASSWORD: password", f"Line 1 incorrect. Expected 'CRACKED_PASSWORD: password', got '{lines[0]}'"
    assert lines[1] == "REDACTED_COUNT: 2", f"Line 2 incorrect. Expected 'REDACTED_COUNT: 2', got '{lines[1]}'"
    assert lines[2] == "CERT_ACTION: REPLACED", f"Line 3 incorrect. Expected 'CERT_ACTION: REPLACED', got '{lines[2]}'"


def test_app_redacted_log_content():
    redacted_log_path = "/home/user/app_redacted.log"
    assert os.path.isfile(redacted_log_path), f"Redacted log missing at {redacted_log_path}"

    with open(redacted_log_path, "r") as f:
        content = f.read()

    expected_content = """[INFO] Application started
[DEBUG] Connecting to AWS with key AKIA[REDACTED] for bucket access.
[INFO] User logged in.
[DEBUG] Backup completed. Used credentials: AKIA[REDACTED] to store payload.
[ERROR] Failed to connect.
"""
    assert content.strip() == expected_content.strip(), "The contents of app_redacted.log do not match the expected redacted output."


def test_new_certificate_exists_and_valid():
    assert_certificate("/home/user/certs/new.crt", "/home/user/certs/new.key")


def find_bash_scripts():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        for name in files:
            path = os.path.join(root, name)
            try:
                with open(path, "rb") as f:
                    first_line = f.readline(256).decode("utf-8", "ignore")
            except OSError:
                continue
            if name.endswith(".sh") or (first_line.startswith("#!") and "bash" in first_line):
                candidates.append(path)
    return sorted(set(candidates))


def install_dynamic_fixture(password, log_content):
    decoys = ["guest" + secrets.token_hex(3), "root" + secrets.token_hex(3), "demo" + secrets.token_hex(3)]
    with open(os.path.join(HOME, "legacy.conf"), "w") as f:
        f.write("server_port: 9090\ndb_user: auditor\ndb_password_hash: " + hashlib.md5(password.encode()).hexdigest() + "\n")
    with open(os.path.join(HOME, "wordlist.txt"), "w") as f:
        f.write("\n".join([decoys[0], password, decoys[1], decoys[2]]) + "\n")
    with open(os.path.join(HOME, "app.log"), "w") as f:
        f.write(log_content)

    for path in [os.path.join(HOME, "audit_report.txt"), os.path.join(HOME, "app_redacted.log"),
                 os.path.join(CERT_DIR, "new.crt"), os.path.join(CERT_DIR, "new.key")]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", os.path.join(CERT_DIR, "legacy.key"),
        "-out", os.path.join(CERT_DIR, "legacy.crt"),
        "-days", "1", "-nodes", "-subj", "/CN=dynamic-legacy.local"
    ])


def validate_dynamic_result(password, expected_log, expected_count):
    report_path = os.path.join(HOME, "audit_report.txt")
    redacted_path = os.path.join(HOME, "app_redacted.log")
    assert os.path.isfile(report_path), "Script did not create audit_report.txt"
    assert os.path.isfile(redacted_path), "Script did not create app_redacted.log"

    with open(report_path) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == [
        f"CRACKED_PASSWORD: {password}",
        f"REDACTED_COUNT: {expected_count}",
        "CERT_ACTION: REPLACED",
    ], f"Dynamic audit report is incorrect: {lines}"

    with open(redacted_path) as f:
        actual_log = f.read()
    assert actual_log == expected_log, "Script did not redact the dynamically generated log correctly"
    assert_certificate(os.path.join(CERT_DIR, "new.crt"), os.path.join(CERT_DIR, "new.key"))


def test_bash_remediation_script_executes_and_handles_derived_inputs():
    candidates = find_bash_scripts()
    assert candidates, "No Bash remediation script was found under /home/user"

    alphabet = string.ascii_uppercase + string.digits
    keys = ["AKIA" + "".join(secrets.choice(alphabet) for _ in range(16)) for _ in range(3)]
    password = "audit" + secrets.token_hex(6)
    log_content = (
        "[INFO] Dynamic audit fixture\n"
        f"[WARN] first credential {keys[0]} was exposed\n"
        f"[DEBUG] paired credentials {keys[1]} and {keys[2]} detected\n"
        "[INFO] lowercase akiaabcdefghijklmnop is not an AWS Access Key ID\n"
    )
    expected_log, expected_count = re.subn(r"AKIA[A-Z0-9]{16}", "AKIA[REDACTED]", log_content)

    failures = []
    for script in candidates:
        install_dynamic_fixture(password, log_content)
        try:
            syntax = subprocess.run(["bash", "-n", script], capture_output=True, text=True)
            if syntax.returncode != 0:
                failures.append(f"{script}: Bash syntax error: {syntax.stderr.strip()}")
                continue
            result = subprocess.run(
                ["bash", script], cwd=HOME, capture_output=True, text=True, timeout=60
            )
            if result.returncode != 0:
                failures.append(f"{script}: exited {result.returncode}: {result.stderr.strip()}")
                continue
            validate_dynamic_result(password, expected_log, expected_count)
            return
        except (AssertionError, subprocess.SubprocessError) as e:
            failures.append(f"{script}: {e}")

    pytest.fail("No Bash remediation script passed dynamic execution:\n" + "\n".join(failures))
TEST_EOF

if LC_ALL=C python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
