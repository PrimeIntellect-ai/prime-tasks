#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import hmac
import hashlib
import secrets
import subprocess
from pathlib import Path

STAGING_TOKEN_PATH = Path("/home/user/staging_token.jwt")
WORDLIST_PATH = Path("/home/user/wordlist.txt")
SECRET_OUTPUT_PATH = Path("/home/user/staging_secret.txt")

ORIGINAL_WORDLIST = (
    b"admin123\n"
    b"password\n"
    b"qwerty\n"
    b"letmein1\n"
    b"spring2024\n"
    b"autumn2023\n"
    b"winter2022\n"
    b"summer2021\n"
    b"hunter2\n"
    b"supersecret\n"
)
ORIGINAL_HEADER_PAYLOAD = b"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiZ3Vlc3QifQ"


def base64url_decode(input_str):
    rem = len(input_str) % 4
    if rem > 0:
        input_str += '=' * (4 - rem)
    return base64.urlsafe_b64decode(input_str)


def base64url_encode(input_bytes):
    return base64.urlsafe_b64encode(input_bytes).rstrip(b'=')


def expected_original_token():
    sig = hmac.new(b"spring2024", ORIGINAL_HEADER_PAYLOAD, hashlib.sha256).digest()
    return ORIGINAL_HEADER_PAYLOAD + b"." + base64url_encode(sig)


def assert_original_staging_fixtures():
    assert STAGING_TOKEN_PATH.is_file(), f"Missing file: {STAGING_TOKEN_PATH}"
    assert WORDLIST_PATH.is_file(), f"Missing file: {WORDLIST_PATH}"
    assert WORDLIST_PATH.read_bytes() == ORIGINAL_WORDLIST, "The supplied staging wordlist was modified."
    assert STAGING_TOKEN_PATH.read_bytes() == expected_original_token(), "The supplied staging JWT was modified."


def test_staging_secret_cracked():
    token_path = "/home/user/staging_token.jwt"
    wordlist_path = "/home/user/wordlist.txt"
    secret_output_path = "/home/user/staging_secret.txt"

    assert_original_staging_fixtures()
    assert os.path.isfile(secret_output_path), f"Missing file: {secret_output_path}"

    with open(token_path, 'r') as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) == 3, "Staging token is not a valid JWT"
    header_payload = f"{parts[0]}.{parts[1]}".encode()
    target_sig = parts[2]

    with open(wordlist_path, 'r') as f:
        words = [line.strip() for line in f if line.strip()]

    # Derive the correct secret from the wordlist
    derived_secret = None
    for word in words:
        sig = hmac.new(word.encode(), header_payload, hashlib.sha256).digest()
        encoded_sig = base64url_encode(sig).decode()
        if encoded_sig == target_sig:
            derived_secret = word
            break

    assert derived_secret is not None, "Could not derive the staging secret from the wordlist and token."

    with open(secret_output_path, 'r') as f:
        student_secret = f.read().strip()

    assert student_secret == derived_secret, f"The cracked secret in {secret_output_path} is incorrect. Expected the derived secret, but got something else."


def find_bash_script_candidates():
    excluded = {
        Path("/home/user/prod_gateway.sh"),
        STAGING_TOKEN_PATH,
        WORDLIST_PATH,
        SECRET_OUTPUT_PATH,
        Path("/home/user/prod_admin.jwt"),
    }
    candidates = []
    for root, _, files in os.walk("/home/user"):
        for name in files:
            path = Path(root) / name
            if path in excluded or path.is_symlink() or not path.is_file():
                continue
            try:
                if path.stat().st_size <= 1024 * 1024:
                    candidates.append(path)
            except OSError:
                pass
    return candidates


def make_test_case(secret, position):
    words = [f"decoy_{secrets.token_hex(6)}" for _ in range(9)]
    words.insert(position, secret)
    sig = hmac.new(secret.encode(), ORIGINAL_HEADER_PAYLOAD, hashlib.sha256).digest()
    token = ORIGINAL_HEADER_PAYLOAD + b"." + base64url_encode(sig)
    wordlist = ("\n".join(words) + "\n").encode()
    return token, wordlist


def test_bash_bruteforce_script_executes_and_derives_secret():
    assert_original_staging_fixtures()
    assert SECRET_OUTPUT_PATH.is_file(), f"Missing file: {SECRET_OUTPUT_PATH}"

    original_token = STAGING_TOKEN_PATH.read_bytes()
    original_wordlist = WORDLIST_PATH.read_bytes()
    original_output = SECRET_OUTPUT_PATH.read_bytes()
    candidates = find_bash_script_candidates()
    assert candidates, "No Bash brute-force script was found under /home/user."

    cases = [
        make_test_case("key_" + secrets.token_hex(8), 2),
        make_test_case("key_" + secrets.token_hex(8), 7),
    ]

    successful_script = None
    try:
        for candidate in candidates:
            passed_all = True
            for token, wordlist in cases:
                STAGING_TOKEN_PATH.write_bytes(token)
                WORDLIST_PATH.write_bytes(wordlist)
                try:
                    SECRET_OUTPUT_PATH.unlink()
                except FileNotFoundError:
                    pass

                try:
                    subprocess.run(
                        ["/bin/bash", str(candidate)],
                        cwd="/home/user",
                        capture_output=True,
                        text=True,
                        timeout=20,
                    )
                except (OSError, subprocess.TimeoutExpired):
                    passed_all = False
                    break

                expected = None
                token_parts = token.decode().split('.')
                signing_input = f"{token_parts[0]}.{token_parts[1]}".encode()
                for word in wordlist.decode().splitlines():
                    sig = hmac.new(word.encode(), signing_input, hashlib.sha256).digest()
                    if base64url_encode(sig).decode() == token_parts[2]:
                        expected = word
                        break

                if expected is None or not SECRET_OUTPUT_PATH.is_file():
                    passed_all = False
                    break
                if SECRET_OUTPUT_PATH.read_text().strip() != expected:
                    passed_all = False
                    break

            if passed_all:
                successful_script = candidate
                break
    finally:
        STAGING_TOKEN_PATH.write_bytes(original_token)
        WORDLIST_PATH.write_bytes(original_wordlist)
        SECRET_OUTPUT_PATH.write_bytes(original_output)

    assert successful_script is not None, "No submitted Bash script successfully brute-forced independently generated staging JWT fixtures."


def test_prod_admin_jwt_structure():
    jwt_path = "/home/user/prod_admin.jwt"
    assert os.path.isfile(jwt_path), f"Missing file: {jwt_path}"

    with open(jwt_path, 'r') as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) >= 2, f"The token in {jwt_path} does not have enough segments to be a JWT."

    header_b64 = parts[0]
    payload_b64 = parts[1]
    sig_b64 = parts[2] if len(parts) == 3 else ""

    try:
        header = json.loads(base64url_decode(header_b64).decode('utf-8'))
        payload = json.loads(base64url_decode(payload_b64).decode('utf-8'))
    except Exception as e:
        assert False, f"Failed to decode and parse header or payload JSON: {e}"

    assert "alg" in header, "Header is missing 'alg' field."
    assert header["alg"].lower() == "none", f"Expected 'alg' to be 'none', got '{header['alg']}'."

    assert "user" in payload, "Payload is missing 'user' field."
    assert payload["user"] == "admin", f"Expected 'user' to be 'admin', got '{payload['user']}'."

    assert sig_b64 == "", "Signature must be empty for 'none' algorithm."


def test_prod_gateway_execution():
    jwt_path = "/home/user/prod_admin.jwt"
    script_path = "/home/user/prod_gateway.sh"

    assert os.path.isfile(jwt_path), f"Missing file: {jwt_path}"
    assert os.path.isfile(script_path), f"Missing file: {script_path}"

    with open(jwt_path, 'r') as f:
        token = f.read().strip()

    result = subprocess.run([script_path, token], capture_output=True, text=True)

    assert result.returncode == 0, f"Script exited with non-zero code {result.returncode}. Stderr: {result.stderr.strip()}"
    output = result.stdout.strip()
    expected_output = "Access Granted: admin"
    assert output == expected_output, f"Script output was '{output}', expected '{expected_output}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
