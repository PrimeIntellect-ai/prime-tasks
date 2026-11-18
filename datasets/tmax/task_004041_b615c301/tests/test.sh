#!/bin/bash
set -e
mkdir -p /logs/verifier
rm -rf /tmp/capacity_verifier
mkdir -m 700 /tmp/capacity_verifier

cat << 'PY_EOF' > /tmp/capacity_verifier/test_final_state.py
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

REPORT = "/home/user/capacity_report.json"
FSTAB = "/home/user/fstab_mock"
CERT = "/home/user/tls.crt"
KEY = "/home/user/tls.key"
OPENSSL = "/usr/bin/openssl"
CURL = "/usr/bin/curl"


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True)


# Derive the required mount point from the supplied fstab rather than trusting a
# hardcoded report value.
assert os.path.isfile(FSTAB), f"File {FSTAB} does not exist."
matches = []
with open(FSTAB, "r", encoding="utf-8") as f:
    for raw_line in f:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) >= 2 and fields[0] == "UUID=A1B2-C3D4":
            matches.append(fields[1])
assert len(matches) == 1, "Expected exactly one fstab entry for UUID A1B2-C3D4."
expected_mount = matches[0]

# Perform the specified health request at verification time. curl exits nonzero
# for connection failures/timeouts; any HTTP status other than 200 is DOWN.
health = subprocess.run(
    [CURL, "--silent", "--show-error", "--output", "/dev/null",
     "--write-out", "%{http_code}", "--max-time", "3",
     "http://127.0.0.1:9090/health"],
    capture_output=True, text=True
)
expected_status = "UP" if health.returncode == 0 and health.stdout.strip() == "200" else "DOWN"

assert os.path.isfile(REPORT), f"File {REPORT} does not exist."
with open(REPORT, "r", encoding="utf-8") as f:
    data = json.load(f)

assert set(data.keys()) == {"timestamp", "target_mount", "service_status"}, \
    "The report must contain exactly timestamp, target_mount, and service_status."
assert data["target_mount"] == expected_mount, \
    f"Expected target_mount derived from fstab to be {expected_mount!r}, got {data['target_mount']!r}."
assert data["service_status"] in ("UP", "DOWN"), "service_status must be UP or DOWN."
assert data["service_status"] == expected_status, \
    f"Expected service_status from the live health check to be {expected_status!r}, got {data['service_status']!r}."

timestamp = data["timestamp"]
assert isinstance(timestamp, str) and re.fullmatch(
    r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} JST", timestamp
), f"Timestamp {timestamp!r} does not match 'YYYY-MM-DD HH:MM:SS JST'."
try:
    report_time = datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S JST").replace(
        tzinfo=ZoneInfo("Asia/Tokyo")
    )
except ValueError as exc:
    raise AssertionError(f"Timestamp {timestamp!r} is not a valid date/time: {exc}")
now_tokyo = datetime.now(ZoneInfo("Asia/Tokyo"))
age = (now_tokyo - report_time).total_seconds()
assert -2 <= age <= 3600, \
    f"Timestamp must be the current Asia/Tokyo time; it is {age:.1f} seconds old."
report_mtime = datetime.fromtimestamp(os.path.getmtime(REPORT), timezone.utc).astimezone(
    ZoneInfo("Asia/Tokyo")
)
assert abs((report_mtime - report_time).total_seconds()) <= 60, \
    "The report timestamp is not contemporaneous with report generation."

assert os.path.isfile(CERT), f"Certificate file {CERT} does not exist."
assert os.path.isfile(KEY), f"Private key file {KEY} does not exist."

try:
    cert_text = run([OPENSSL, "x509", "-in", CERT, "-text", "-noout"]).stdout
except subprocess.CalledProcessError as exc:
    raise AssertionError(f"Failed to read certificate with openssl: {exc.stderr}")
assert "CN = localhost" in cert_text or "CN=localhost" in cert_text, \
    "The certificate Common Name (CN) is not set to 'localhost'."
assert "Public Key Algorithm: rsaEncryption" in cert_text, \
    "The certificate public key is not RSA."
assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_text), \
    "The certificate must contain an RSA-2048 public key."

try:
    key_check = run([OPENSSL, "rsa", "-in", KEY, "-check", "-noout"])
except subprocess.CalledProcessError as exc:
    raise AssertionError(f"Failed to verify private key with openssl: {exc.stderr}")
assert "RSA key ok" in key_check.stdout + key_check.stderr, \
    "The private key is not a valid RSA key."
key_text = run([OPENSSL, "rsa", "-in", KEY, "-text", "-noout"]).stdout
assert re.search(r"(?:Private-Key|RSA Private-Key):\s*\(2048 bit", key_text), \
    "The private key must be RSA-2048."

cert_pub = run([OPENSSL, "x509", "-in", CERT, "-pubkey", "-noout"]).stdout.strip()
key_pub = run([OPENSSL, "pkey", "-in", KEY, "-pubout"]).stdout.strip()
assert cert_pub == key_pub, "The TLS certificate and private key do not form a pair."

subject = run([OPENSSL, "x509", "-in", CERT, "-noout", "-subject", "-nameopt", "RFC2253"]).stdout.strip()
issuer = run([OPENSSL, "x509", "-in", CERT, "-noout", "-issuer", "-nameopt", "RFC2253"]).stdout.strip()
subject_dn = subject.split("=", 1)[1].strip()
issuer_dn = issuer.split("=", 1)[1].strip()
assert re.search(r"(?:^|,)CN=localhost(?:,|$)", subject_dn), \
    "The certificate subject CN must be localhost."
assert subject_dn == issuer_dn, "The certificate is not self-signed."
run([OPENSSL, "verify", "-CAfile", CERT, CERT])

dates = run([OPENSSL, "x509", "-in", CERT, "-noout", "-startdate", "-enddate"]).stdout.splitlines()
values = dict(line.split("=", 1) for line in dates)
not_before = datetime.strptime(values["notBefore"], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
not_after = datetime.strptime(values["notAfter"], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
assert abs((not_after - not_before).total_seconds() - 365 * 24 * 60 * 60) <= 5, \
    "The certificate validity period must be 365 days."
now_utc = datetime.now(timezone.utc)
assert not_before <= now_utc <= not_after, "The certificate is not currently valid."
PY_EOF

if python3 -I /tmp/capacity_verifier/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
