#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import importlib.machinery
import os
import ssl
from http.cookies import SimpleCookie

SUMMARY = "/home/user/rotation_summary.txt"
PYC = "/home/user/auth_handler.pyc"
CA = "/home/user/ca.crt"


def derive_expected_values():
    loader = importlib.machinery.SourcelessFileLoader("verifier_auth_handler", PYC)
    module = loader.load_module()
    old_key = module.get_legacy_key()

    context = ssl.create_default_context(cafile=CA)
    connection = http.client.HTTPSConnection(
        "127.0.0.1", 8443, context=context, timeout=5
    )
    connection.request(
        "POST",
        "/rotate",
        body='{"new_key": "secure_new_key_2024"}',
        headers={
            "Authorization": f"Bearer {old_key}",
            "Content-Type": "application/json",
        },
    )

    certificate = connection.sock.getpeercert()
    response = connection.getresponse()
    response.read()
    assert response.status == 200, f"Rotation endpoint returned HTTP {response.status}"

    cookie = SimpleCookie()
    cookie.load(response.getheader("Set-Cookie", ""))
    assert "session_token" in cookie, "Rotation response did not contain session_token"
    session_token = cookie["session_token"].value

    common_names = [
        value
        for rdn in certificate.get("subject", ())
        for key, value in rdn
        if key == "commonName"
    ]
    assert len(common_names) == 1, "Server certificate must have exactly one Subject CN"
    return [old_key, session_token, common_names[0]]


def test_rotation_summary_exists():
    assert os.path.exists(SUMMARY), (
        "The file /home/user/rotation_summary.txt does not exist. "
        "Make sure you created it in the correct location."
    )


def test_rotation_summary_content():
    expected_lines = derive_expected_values()

    with open(SUMMARY, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) >= 3, "The rotation_summary.txt file must contain exactly three lines."
    assert content[0].strip() == expected_lines[0], "Line 1 contains the wrong legacy key."
    assert content[1].strip() == expected_lines[1], "Line 2 contains the wrong session_token."
    assert content[2].strip() == expected_lines[2], "Line 3 contains the wrong certificate CN."
    assert len(content) == 3, (
        "The rotation_summary.txt file should contain exactly three lines, but it has more."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
