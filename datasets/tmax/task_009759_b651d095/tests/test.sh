#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import secrets
import subprocess
from datetime import datetime, timedelta, timezone
import pytest


def test_capacity_report():
    report_path = "/home/user/capacity_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} is missing."
    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = [
        "10.0.0.5: 350000",
        "172.16.0.2: 45000",
        "192.168.1.20: 8000"
    ]
    assert lines == expected, f"Content of {report_path} is incorrect. Expected {expected}, got {lines}."


def test_tls_certs():
    cert_path = "/home/user/certs/cert.pem"
    key_path = "/home/user/certs/key.pem"
    assert os.path.isfile(cert_path), f"Certificate file {cert_path} is missing."
    assert os.path.isfile(key_path), f"Key file {key_path} is missing."

    # Check valid, unencrypted RSA key.
    result = subprocess.run(
        ["openssl", "rsa", "-in", key_path, "-check", "-noout"],
        capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Invalid RSA key: {result.stderr}"

    # Keep the original certificate validity check.
    result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-text"],
        capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Invalid certificate: {result.stderr}"
    assert "Signature Algorithm" in result.stdout, "Certificate does not appear to be a valid x509 cert."

    # Require an exact 2048-bit RSA private key.
    key_text = subprocess.run(
        ["openssl", "rsa", "-in", key_path, "-text", "-noout"],
        capture_output=True, text=True, timeout=10
    )
    assert key_text.returncode == 0, f"Could not inspect RSA key: {key_text.stderr}"
    match = re.search(r"(?:Private-Key|RSA Private-Key):\s*\((\d+) bit", key_text.stdout)
    assert match and int(match.group(1)) == 2048, "Private key is not a 2048-bit RSA key."

    # Require the certificate public key to correspond to the submitted private key.
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"],
        capture_output=True, timeout=10
    )
    assert key_pub.returncode == 0, f"Could not derive public key from private key: {key_pub.stderr.decode(errors='replace')}"

    cert_pub_pem = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"],
        capture_output=True, timeout=10
    )
    assert cert_pub_pem.returncode == 0, f"Could not extract certificate public key: {cert_pub_pem.stderr.decode(errors='replace')}"
    cert_pub = subprocess.run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input=cert_pub_pem.stdout, capture_output=True, timeout=10
    )
    assert cert_pub.returncode == 0, f"Could not parse certificate public key: {cert_pub.stderr.decode(errors='replace')}"
    assert key_pub.stdout == cert_pub.stdout, "Certificate and private key do not correspond."

    # Require a self-signed certificate.
    verify = subprocess.run(
        ["openssl", "verify", "-CAfile", cert_path, cert_path],
        capture_output=True, text=True, timeout=10
    )
    assert verify.returncode == 0, f"Certificate is not validly self-signed: {verify.stderr}"

    # Check that the full certificate validity period is at least 365 days and is current.
    dates = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-dates"],
        capture_output=True, text=True, timeout=10
    )
    assert dates.returncode == 0, f"Could not inspect certificate dates: {dates.stderr}"
    values = dict(line.split("=", 1) for line in dates.stdout.strip().splitlines() if "=" in line)
    assert "notBefore" in values and "notAfter" in values, "Certificate validity dates are missing."
    fmt = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.strptime(values["notBefore"], fmt).replace(tzinfo=timezone.utc)
    not_after = datetime.strptime(values["notAfter"], fmt).replace(tzinfo=timezone.utc)
    assert not_after - not_before >= timedelta(days=365), "Certificate validity period is less than 365 days."
    now = datetime.now(timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."


def test_backup_script_functionality():
    script_path = "/home/user/backup_logs.sh"
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."

    log_path = "/home/user/app_logs/access.log"
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    payload = ("random backup test " + secrets.token_hex(64) + "\n").encode() + secrets.token_bytes(4096)
    with open(log_path, "wb") as f:
        f.write(payload)

    # Remove possible stale outputs for dates around a midnight boundary.
    start = datetime.now()
    possible_dates = {start.date() - timedelta(days=1), start.date(), start.date() + timedelta(days=1)}
    for day in possible_dates:
        path = f"/home/user/backup/access_{day.strftime('%Y-%m-%d')}.log.gz"
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Backup script failed to execute. stderr: {result.stderr}"

    finish = datetime.now()
    candidate_dates = {start.date(), finish.date()}
    candidates = [
        f"/home/user/backup/access_{day.strftime('%Y-%m-%d')}.log.gz"
        for day in candidate_dates
    ]
    existing = [path for path in candidates if os.path.isfile(path)]
    assert existing, f"Backup file was not created at any expected dated path: {candidates}"
    backup_path = existing[0]

    result = subprocess.run(["gzip", "-t", backup_path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Backup file {backup_path} is not a valid gzip file."

    with gzip.open(backup_path, "rb") as f:
        restored = f.read()
    assert restored == payload, "Decompressed backup does not exactly match the original log contents."

    assert os.path.isfile(log_path), f"Original log file {log_path} was deleted instead of truncated."
    assert os.path.getsize(log_path) == 0, f"Original log file {log_path} was not truncated to zero bytes."


def test_crontab_scheduling():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab. Has it been configured?"

    lines = result.stdout.strip().split('\n')
    found = False
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("0 0 * * *") and "/home/user/backup_logs.sh" in line:
            found = True
            break

    assert found, "Crontab does not contain the correct scheduled task (0 0 * * * /home/user/backup_logs.sh)."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
