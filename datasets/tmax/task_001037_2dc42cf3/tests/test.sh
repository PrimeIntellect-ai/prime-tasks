#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import hmac
import hashlib
import subprocess
import pytest

def decode_jwt_part(part):
    # Add padding if necessary
    part += '=' * (-len(part) % 4)
    return json.loads(base64.urlsafe_b64decode(part).decode('utf-8'))

def get_expected_values():
    requests_path = "/home/user/requests.json"
    wordlist_path = "/home/user/wordlist.txt"
    cert_path = "/home/user/server.crt"

    with open(requests_path, "r") as f:
        logs = json.load(f)

    with open(wordlist_path, "r") as f:
        passwords = [line.strip() for line in f if line.strip()]

    alg_none_user = None
    cracked_secret = None

    for log in logs:
        auth = log.get("authorization", "")
        if auth.startswith("Bearer "):
            token = auth.split(" ")[1]
            parts = token.split(".")
            if len(parts) >= 2:
                header = decode_jwt_part(parts[0])
                payload = decode_jwt_part(parts[1])

                alg = header.get("alg", "").lower()
                if alg == "none":
                    alg_none_user = payload.get("username")
                elif alg == "hs256" and len(parts) == 3:
                    # Attempt to crack
                    msg = f"{parts[0]}.{parts[1]}".encode('utf-8')
                    sig = parts[2]
                    for pwd in passwords:
                        expected_sig = base64.urlsafe_b64encode(
                            hmac.new(pwd.encode('utf-8'), msg, hashlib.sha256).digest()
                        ).replace(b'=', b'').decode('utf-8')
                        if expected_sig == sig:
                            cracked_secret = pwd
                            break

    # Extract issuer CN using openssl
    cert_issuer = None
    try:
        result = subprocess.run(
            ["openssl", "x509", "-in", cert_path, "-noout", "-issuer"],
            capture_output=True, text=True, check=True
        )
        # Output format usually: issuer= /C=US/ST=State/L=City/O=Organization/CN=InternalCorp
        # or issuer=C = US, ST = State, L = City, O = Organization, CN = InternalCorp
        output = result.stdout.strip()
        if "CN=" in output:
            cert_issuer = output.split("CN=")[1].split(",")[0].strip()
        elif "CN =" in output:
            cert_issuer = output.split("CN =")[1].split(",")[0].strip()
    except Exception:
        pass

    return cracked_secret, alg_none_user, cert_issuer

def test_audit_trail_content():
    audit_path = "/home/user/audit_trail.txt"
    assert os.path.exists(audit_path), f"Audit trail file {audit_path} does not exist."
    assert os.path.isfile(audit_path), f"Path {audit_path} is not a file."

    expected_secret, expected_user, expected_issuer = get_expected_values()

    assert expected_secret is not None, "Could not derive the cracked secret from the provided files."
    assert expected_user is not None, "Could not derive the alg=none user from the provided files."
    assert expected_issuer is not None, "Could not derive the certificate issuer from the provided files."

    with open(audit_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    parsed_data = {}
    for line in lines:
        if ":" in line:
            key, val = line.split(":", 1)
            parsed_data[key] = val

    assert "CRACKED_SECRET" in parsed_data, "CRACKED_SECRET is missing from the audit trail."
    assert parsed_data["CRACKED_SECRET"] == expected_secret, f"CRACKED_SECRET is incorrect. Expected {expected_secret}."

    assert "ALG_NONE_USER" in parsed_data, "ALG_NONE_USER is missing from the audit trail."
    assert parsed_data["ALG_NONE_USER"] == expected_user, f"ALG_NONE_USER is incorrect. Expected {expected_user}."

    assert "CERT_ISSUER" in parsed_data, "CERT_ISSUER is missing from the audit trail."
    assert parsed_data["CERT_ISSUER"] == expected_issuer, f"CERT_ISSUER is incorrect. Expected {expected_issuer}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
