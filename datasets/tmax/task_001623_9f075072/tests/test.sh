#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import json
import os
import secrets
import shlex
import subprocess


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_jwt(payload, secret=b"BlueberrySky123", header=None):
    if header is None:
        header = {"alg": "HS256", "typ": "JWT"}
    encoded_header = b64url(json.dumps(header, separators=(",", ":")).encode())
    encoded_payload = b64url(json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode())
    signing_input = f"{encoded_header}.{encoded_payload}".encode("ascii")
    signature = b64url(hmac.new(secret, signing_input, hashlib.sha256).digest())
    return f"{encoded_header}.{encoded_payload}.{signature}"


def run_filter(token):
    result = subprocess.run(
        ["/home/user/jwt_filter.sh"],
        input=token.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    return result.stdout


def test_cwe_identified():
    path = "/home/user/cwe_identified.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content in ["CWE-347", "CWE-287"], f"Incorrect CWE identified. Found: {content}"


def test_vulnerable_app_checksum():
    app_path = "/home/user/vulnerable_app.sh"
    checksum_path = "/home/user/checksums.txt"
    assert os.path.isfile(app_path), f"Missing required file: {app_path}"
    assert os.path.isfile(checksum_path), f"Missing required file: {checksum_path}"

    original = b'''#!/bin/bash
TOKEN=$1
HEADER=$(echo $TOKEN | cut -d. -f1 | base64 -d 2>/dev/null)
ALG=$(echo $HEADER | grep -o '"alg":"none"' || true)
if [ -n "$ALG" ]; then
  echo "Access Granted (Bypass)"
else
  echo "Checking signature..."
fi
'''
    expected_digest = hashlib.sha256(original).hexdigest()
    with open(checksum_path, "r") as f:
        checksum_content = f.read().strip()
    assert checksum_content == f"{expected_digest}  vulnerable_app.sh", "checksums.txt does not contain the original expected checksum"

    result = subprocess.run(
        ["sha256sum", "-c", "checksums.txt"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"vulnerable_app.sh failed checksum verification: {result.stdout}{result.stderr}"


def test_block_rule():
    path = "/home/user/block_rule.txt"
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    try:
        command = shlex.split(content)
    except ValueError as exc:
        raise AssertionError(f"Invalid command syntax in block_rule.txt: {exc}")
    expected = ["iptables", "-A", "INPUT", "-s", "198.51.100.45", "-p", "tcp", "-j", "DROP"]
    assert command == expected, f"block_rule.txt must contain exactly: {' '.join(expected)}"


def test_jwt_filter_executable():
    path = "/home/user/jwt_filter.sh"
    assert os.path.isfile(path), f"Missing required file: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"


def test_jwt_filter_original_corpus():
    script_path = "/home/user/jwt_filter.sh"
    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"

    evil_bypassed = []
    clean_modified = []
    for filename in os.listdir(evil_dir):
        filepath = os.path.join(evil_dir, filename)
        if not os.path.isfile(filepath):
            continue
        with open(filepath, "rb") as f:
            token_data = f.read()
        try:
            result = subprocess.run([script_path], input=token_data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            if result.stdout.strip() != b"REJECT":
                evil_bypassed.append(filename)
        except Exception as exc:
            evil_bypassed.append(f"{filename} (error: {exc})")

    for filename in os.listdir(clean_dir):
        filepath = os.path.join(clean_dir, filename)
        if not os.path.isfile(filepath):
            continue
        with open(filepath, "rb") as f:
            token_data = f.read()
        try:
            result = subprocess.run([script_path], input=token_data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            if result.stdout.strip() != b"ACCEPT":
                clean_modified.append(filename)
        except Exception as exc:
            clean_modified.append(f"{filename} (error: {exc})")

    errors = []
    if evil_bypassed:
        errors.append(f"Evil tokens bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"Clean tokens rejected: {', '.join(clean_modified)}")
    assert not errors, "Adversarial corpus test failed:\n" + "\n".join(errors)


def test_jwt_filter_randomized_validation():
    nonce = secrets.token_hex(24)
    valid_tokens = []
    for i in range(12):
        valid_tokens.append(make_jwt({
            "user": f"random-{i}-{secrets.token_hex(12)}",
            "admin": bool(i % 2),
            "nonce": nonce,
            "value": secrets.randbits(96),
        }))

    for token in valid_tokens:
        assert run_filter(token) == b"ACCEPT\n", "A freshly generated, correctly signed HS256 token was not accepted exactly"

    evil_tokens = []
    none_header = b64url(json.dumps({"typ": "JWT", "alg": "none"}, separators=(",", ":")).encode())
    none_payload = b64url(json.dumps({"nonce": nonce, "admin": True}, separators=(",", ":")).encode())
    evil_tokens.append(f"{none_header}.{none_payload}.")
    evil_tokens.append(make_jwt({"nonce": nonce, "kind": "wrong-secret"}, secret=secrets.token_bytes(32)))

    original = valid_tokens[0]
    header, payload, signature = original.split(".")
    replacement_payload = b64url(json.dumps({"nonce": nonce, "admin": True, "tampered": secrets.token_hex(8)}, separators=(",", ":")).encode())
    evil_tokens.append(f"{header}.{replacement_payload}.{signature}")

    replacement_signature = b64url(secrets.token_bytes(32))
    evil_tokens.append(f"{header}.{payload}.{replacement_signature}")
    evil_tokens.extend([
        "",
        "not-a-jwt",
        "a.b",
        "a.b.c.d",
        "@@@.@@@.@@@",
        f"{header}.{payload}.",
    ])

    for token in evil_tokens:
        assert run_filter(token) == b"REJECT\n", "A randomized forged, none-algorithm, or malformed token was not rejected exactly"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
