#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import base64
import hashlib
import json
import subprocess

TOKEN_PATH = "/home/user/evasion.token"
REPORT_PATH = "/home/user/exfiltration_report.txt"
VERIFIER_PATH = "/home/user/verify_token.sh"


def test_evasion_token_permissions():
    assert os.path.exists(TOKEN_PATH), f"Token file missing at {TOKEN_PATH}"

    st = os.stat(TOKEN_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Expected permissions 0o400 for {TOKEN_PATH}, got {oct(perms)}"


def test_evasion_token_content():
    assert os.path.exists(TOKEN_PATH), f"Token file missing at {TOKEN_PATH}"

    with open(TOKEN_PATH, "rb") as f:
        token_bytes = f.read()

    assert not token_bytes.endswith(b"\n"), "Token file should not have a trailing newline."

    token_str = token_bytes.decode("utf-8")
    parts = token_str.split(".")
    assert len(parts) == 3, "Token must be in header.payload.signature format."

    header_b64, payload_b64, signature_b64 = parts
    assert signature_b64 == "", "Signature part of the token should be empty."

    try:
        header_padded = header_b64 + "=" * (-len(header_b64) % 4)
        header_json = base64.b64decode(header_padded).decode("utf-8")
    except Exception as e:
        assert False, f"Failed to base64 decode header: {e}"

    assert '"alg":"none"' in header_json.replace(" ", ""), 'Header must contain "alg":"none"'
    try:
        header_obj = json.loads(header_json)
    except json.JSONDecodeError as e:
        assert False, f"Header must be valid JSON: {e}"
    assert isinstance(header_obj, dict), "Header must decode to a JSON object."
    assert header_obj.get("alg") == "none", 'Header algorithm must be "none".'

    try:
        payload_padded = payload_b64 + "=" * (-len(payload_b64) % 4)
        payload_json = base64.b64decode(payload_padded).decode("utf-8")
    except Exception as e:
        assert False, f"Failed to base64 decode payload: {e}"

    try:
        payload_obj = json.loads(payload_json)
    except json.JSONDecodeError as e:
        assert False, f"Payload must be valid JSON: {e}"
    assert payload_obj == {"role": "admin"}, 'Payload must decode to exactly {"role":"admin"}'


def test_token_bypasses_target_verifier():
    assert os.path.isfile(VERIFIER_PATH), f"Verifier missing at {VERIFIER_PATH}"
    result = subprocess.run(
        [VERIFIER_PATH, TOKEN_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Target verifier rejected the token (exit {result.returncode}): "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == "Granted admin access.", (
        f"Unexpected target verifier output: {result.stdout!r}"
    )


def test_report_content():
    assert os.path.exists(REPORT_PATH), f"Report file missing at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, "Report file must contain exactly two lines."

    cwe_line = lines[0].strip()
    hash_line = lines[1].strip()

    assert cwe_line == "CWE-347", f"Expected first line to be CWE-347, got {cwe_line}"
    assert lines[0] == cwe_line, "The CWE report line must not contain surrounding whitespace."

    assert os.path.exists(TOKEN_PATH), f"Token file missing at {TOKEN_PATH}"
    with open(TOKEN_PATH, "rb") as f:
        token_bytes = f.read()

    expected_hash = hashlib.sha256(token_bytes).hexdigest()
    assert hash_line == expected_hash, f"Expected hash {expected_hash}, got {hash_line}"
    assert lines[1] == hash_line, "The hash report line must not contain surrounding whitespace."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
