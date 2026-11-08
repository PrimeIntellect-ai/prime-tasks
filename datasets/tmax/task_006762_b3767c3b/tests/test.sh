#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import itertools
import urllib.parse
import pytest

def get_expected_data():
    # Read the original encrypted file to compute expected outputs dynamically
    enc_path = "/home/user/exfil_logs.enc"
    assert os.path.exists(enc_path), f"Source file {enc_path} is missing."

    with open(enc_path, "r") as f:
        encoded = f.read().strip()

    xored = base64.b64decode(encoded)
    key = "INTRUSION"
    plain_text = bytes(a ^ ord(b) for a, b in zip(xored, itertools.cycle(key))).decode('utf-8')

    malicious_uris = set()
    legit_domains = set()

    for line in plain_text.strip().split('\n'):
        if not line.strip():
            continue
        data = json.loads(line)
        blocked_uri = data.get("csp-report", {}).get("blocked-uri", "")

        if "malware" in blocked_uri or blocked_uri.endswith(".exe"):
            malicious_uris.add(blocked_uri)
        else:
            parsed = urllib.parse.urlparse(blocked_uri)
            domain = f"{parsed.scheme}://{parsed.netloc}"
            legit_domains.add(domain)

    sorted_malicious = sorted(list(malicious_uris))
    sorted_domains = sorted(list(legit_domains))

    expected_csp = "Content-Security-Policy: script-src 'self'"
    if sorted_domains:
        expected_csp += " " + " ".join(sorted_domains)
    expected_csp += ";"

    return plain_text, sorted_malicious, expected_csp

def test_decrypted_log():
    expected_plain_text, _, _ = get_expected_data()

    decrypted_path = "/home/user/decrypted.log"
    assert os.path.exists(decrypted_path), f"File {decrypted_path} is missing."

    with open(decrypted_path, "r") as f:
        actual_plain_text = f.read()

    # Compare parsed JSON to handle formatting differences
    expected_lines = [json.loads(line) for line in expected_plain_text.strip().split('\n') if line.strip()]
    actual_lines = [json.loads(line) for line in actual_plain_text.strip().split('\n') if line.strip()]

    assert actual_lines == expected_lines, "Decrypted JSON data does not match the expected content."

def test_threats_txt():
    _, expected_malicious, _ = get_expected_data()

    threats_path = "/home/user/threats.txt"
    assert os.path.exists(threats_path), f"File {threats_path} is missing."

    with open(threats_path, "r") as f:
        actual_malicious = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert actual_malicious == expected_malicious, f"Contents of {threats_path} do not match the expected malicious URIs."

def test_new_csp_txt():
    _, _, expected_csp = get_expected_data()

    csp_path = "/home/user/new_csp.txt"
    assert os.path.exists(csp_path), f"File {csp_path} is missing."

    with open(csp_path, "r") as f:
        actual_csp = f.read().strip()

    assert actual_csp == expected_csp, f"Contents of {csp_path} do not match the expected CSP header."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
