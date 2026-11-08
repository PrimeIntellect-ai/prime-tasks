#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib.util
import json
import os
import secrets
import subprocess
import sys

TOKEN_FILE = "/home/user/final_token.txt"
GENERATOR_FILE = "/home/user/auth_generator.py"


def expected_token(user, role, exp):
    header = {"alg": "CUSTOM", "typ": "AUTH"}
    payload = {"user": user, "role": role, "exp": exp}

    h_b64 = base64.urlsafe_b64encode(
        json.dumps(header, separators=(',', ':')).encode()
    ).decode().rstrip('=')
    p_b64 = base64.urlsafe_b64encode(
        json.dumps(payload, separators=(',', ':')).encode()
    ).decode().rstrip('=')

    data = f"{h_b64}.{p_b64}"
    h = 5381
    for c in data:
        h = ((h << 5) + h) + ord(c)
    checksum = f"{abs(h) % 1000000:06d}"
    return f"{data}.{checksum}"


def call_generator(user, role, exp):
    invocation = r'''
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location("submitted_auth_generator", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
args = json.loads(sys.argv[2])
result = module.generate_token(args["user"], args["role"], args["exp"])
sys.stdout.write(json.dumps(result))
'''
    args = json.dumps({"user": user, "role": role, "exp": exp})
    proc = subprocess.run(
        [sys.executable, "-c", invocation, GENERATOR_FILE, args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"auth_generator.py failed when imported and called: {proc.stderr}"
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"generate_token did not produce a clean return value: {proc.stdout!r}") from exc


def test_generator_updated_and_functional():
    assert os.path.exists(GENERATOR_FILE), f"File missing: {GENERATOR_FILE}"
    assert os.path.isfile(GENERATOR_FILE), f"Not a file: {GENERATOR_FILE}"

    nonce = secrets.token_hex(12)
    cases = [
        (f"user-{nonce}", "admin/test", secrets.randbelow(2_000_000_000)),
        (f"symbols+/{nonce}", "role?value", secrets.randbelow(2_000_000_000)),
        (f"unicode-ñ-{nonce}", "ops", secrets.randbelow(2_000_000_000)),
    ]
    for user, role, exp in cases:
        actual = call_generator(user, role, exp)
        assert actual == expected_token(user, role, exp), (
            f"generate_token returned an incorrect token for {(user, role, exp)!r}"
        )


def test_script_execution_and_final_token_correct():
    assert os.path.exists(TOKEN_FILE), f"File missing: {TOKEN_FILE}"
    assert os.path.isfile(TOKEN_FILE), f"Not a file: {TOKEN_FILE}"

    expected = expected_token("integration_tester", "admin", 1735689600)

    proc = subprocess.run(
        [sys.executable, GENERATOR_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, f"auth_generator.py failed when executed: {proc.stderr.decode(errors='replace')}"
    assert proc.stdout == (expected + "\n").encode(), (
        "Executing auth_generator.py did not generate the required token"
    )

    with open(TOKEN_FILE, "rb") as f:
        actual = f.read()
    assert actual == expected.encode(), (
        f"Token in {TOKEN_FILE} is incorrect or contains extra whitespace/newlines. "
        f"Expected {expected.encode()!r}, got {actual!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
