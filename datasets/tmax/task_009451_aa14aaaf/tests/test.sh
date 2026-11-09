#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
from html.parser import HTMLParser
import pytest

PAYLOAD_FILE = "/home/user/payload.hex"
KEY = b"REDSQUADRONKEY12"
IV = b"INITIALVECTOR123"


def decrypt_aes_cbc(hex_data: str, key: bytes, iv: bytes) -> bytes:
    key_hex = key.hex()
    iv_hex = iv.hex()

    try:
        bin_data = bytes.fromhex(hex_data)
    except ValueError:
        raise ValueError("Payload is not a valid hex string.")

    process = subprocess.run(
        ["openssl", "enc", "-d", "-aes-128-cbc", "-K", key_hex, "-iv", iv_hex],
        input=bin_data,
        capture_output=True
    )
    if process.returncode != 0:
        raise ValueError(f"Decryption failed: {process.stderr.decode(errors='ignore')}")

    return process.stdout


class DetailsParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.details_tags = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "details":
            self.details_tags.append(attrs)


def test_payload_file_exists():
    assert os.path.exists(PAYLOAD_FILE), f"File {PAYLOAD_FILE} does not exist."


def test_payload_contents():
    with open(PAYLOAD_FILE, "r") as f:
        hex_data = f.read().strip()

    assert hex_data, "Payload file is empty."

    try:
        plaintext_bytes = decrypt_aes_cbc(hex_data, KEY, IV)
    except Exception as e:
        pytest.fail(f"Failed to decrypt payload: {e}")

    try:
        plaintext = plaintext_bytes.decode("utf-8")
        data = json.loads(plaintext)
    except Exception as e:
        pytest.fail(f"Decrypted plaintext is not valid JSON: {e}")

    assert data.get("username") == "admin", "Username is not admin."

    bio = data.get("bio", "")
    bio_lower = bio.lower()

    blocked = ["script", "onload", "onerror", "javascript:", "eval"]
    for b in blocked:
        assert b not in bio_lower, f"Payload contains blocked WAF keyword: {b}"

    assert "<details" in bio_lower, "Payload missing <details> tag."
    assert "ontoggle=" in bio_lower.replace(" ", ""), "Payload missing ontoggle attribute."
    assert "console.log(document.cookie)" in bio, "Payload does not execute exact required JS."
    assert "open" in bio_lower, "Payload missing 'open' attribute to trigger automatically."

    parser = DetailsParser()
    try:
        parser.feed(bio)
        parser.close()
    except Exception as e:
        pytest.fail(f"Bio is not parseable HTML: {e}")

    valid_details = False
    for attrs in parser.details_tags:
        attr_names = [name.lower() for name, _ in attrs]
        toggle_values = [value for name, value in attrs if name.lower() == "ontoggle"]
        if (
            "open" in attr_names
            and len(toggle_values) == 1
            and toggle_values[0] == "console.log(document.cookie)"
        ):
            valid_details = True
            break

    assert valid_details, (
        "Payload must contain an actual <details> element with an open attribute "
        "and exactly one ontoggle handler executing console.log(document.cookie)."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
