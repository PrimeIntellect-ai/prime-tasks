#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import datetime
import glob
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import subprocess

import pytest

HOME = "/home/user"
LOG_PATH = "/home/user/logs/auth.log"
BLOCKED_PATH = "/home/user/blocked_ips.txt"
TOKEN_PATH = "/home/user/new_token.txt"

CANONICAL_LOG = """[2023-10-24 10:00:01] IP: 192.168.1.15 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMSIsIm1hbGljaW91cyI6ZmFsc2V9.dummy_sig
[2023-10-24 10:05:22] IP: 10.0.5.55 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJoYWNrZXIiLCJtYWxpY2lvdXMiOnRydWV9.dummy_sig
[2023-10-24 10:10:00] IP: 172.16.0.4 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJndWVzdCIsIm1hbGljaW91cyI6ZmFsc2V9.dummy_sig
[2023-10-24 10:15:10] IP: 10.0.5.55 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJyb290IiwibWFsaWNpb3VzIjp0cnVlfQ.dummy_sig
[2023-10-24 10:20:00] IP: 192.168.100.2 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZG1pbiIsIm1hbGljaW91cyI6dHJ1ZX0.dummy_sig
"""


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def openssl(*args):
    result = run(["openssl", *args])
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout


def cert_field(path, field):
    output = openssl("x509", "-in", path, "-noout", f"-{field}", "-nameopt", "RFC2253").strip()
    return output.split("=", 1)[1].strip()


def cert_dates(path):
    output = openssl("x509", "-in", path, "-noout", "-startdate", "-enddate")
    values = dict(line.strip().split("=", 1) for line in output.splitlines())
    fmt = "%b %d %H:%M:%S %Y %Z"
    return (
        datetime.datetime.strptime(values["notBefore"], fmt).replace(tzinfo=datetime.timezone.utc),
        datetime.datetime.strptime(values["notAfter"], fmt).replace(tzinfo=datetime.timezone.utc),
    )


def python_scripts():
    return sorted(
        path for path in glob.glob("/home/user/**/*.py", recursive=True)
        if os.path.isfile(path)
    )


def execute_script(path):
    try:
        return subprocess.run(
            ["python3", path], cwd=HOME, capture_output=True, text=True, timeout=15
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def uses_pyjwt_encode(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            tree = ast.parse(handle.read())
    except Exception:
        return False

    imported = False
    encode_call = False
    jwt_aliases = set()
    direct_encode_names = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "jwt" or alias.name.startswith("jwt."):
                    imported = True
                    jwt_aliases.add(alias.asname or alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom) and node.module and (
            node.module == "jwt" or node.module.startswith("jwt.")
        ):
            imported = True
            for alias in node.names:
                if alias.name == "encode":
                    direct_encode_names.add(alias.asname or alias.name)
        elif isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name) and func.id in direct_encode_names:
                encode_call = True
            elif isinstance(func, ast.Attribute) and func.attr == "encode":
                root = func.value
                while isinstance(root, ast.Attribute):
                    root = root.value
                if isinstance(root, ast.Name) and (root.id in jwt_aliases or imported):
                    encode_call = True

    return imported and encode_call


def read_and_validate_token():
    assert os.path.isfile(TOKEN_PATH), f"Missing token file at {TOKEN_PATH}"
    with open(TOKEN_PATH, "r", encoding="utf-8") as handle:
        token = handle.read().strip()

    parts = token.split(".")
    assert len(parts) == 3, "Token in new_token.txt must have three JWT segments"
    header_b64, payload_b64, sig_b64 = parts

    def decode_b64(data):
        return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))

    try:
        header = json.loads(decode_b64(header_b64))
        payload = json.loads(decode_b64(payload_b64))
    except Exception as exc:
        pytest.fail(f"Failed to decode JWT header or payload: {exc}")

    assert header.get("alg") == "HS256", f"Expected algorithm HS256, got {header.get('alg')}"
    assert payload == {"sub": "admin", "role": "superuser", "rotated": True}

    message = f"{header_b64}.{payload_b64}".encode()
    expected = hmac.new(b"NewSecureRotatedSecret_99!", message, hashlib.sha256).digest()
    expected_b64 = base64.urlsafe_b64encode(expected).decode().rstrip("=")
    assert sig_b64 == expected_b64, "JWT signature is invalid"
    return token


def make_test_token(payload):
    def enc(value):
        raw = json.dumps(value, separators=(",", ":")).encode()
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")
    return f'{enc({"alg": "HS256", "typ": "JWT"})}.{enc(payload)}.AA'


def expected_from_log(path):
    expected_ips = set()
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            match = re.search(r"IP:\s+(\S+)\s+Token:\s+(\S+)", line)
            if not match:
                continue
            ip_str, token = match.groups()
            parts = token.split(".")
            if len(parts) >= 2:
                try:
                    payload_raw = base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4))
                    payload = json.loads(payload_raw)
                    if payload.get("malicious") is True:
                        expected_ips.add(ip_str)
                except Exception:
                    continue
    return sorted(expected_ips, key=ipaddress.ip_address)


def read_blocked():
    assert os.path.isfile(BLOCKED_PATH), f"Missing blocked IPs file at {BLOCKED_PATH}"
    with open(BLOCKED_PATH, "r", encoding="utf-8") as handle:
        return [line.strip() for line in handle if line.strip()]


def test_input_log_was_not_modified():
    assert os.path.isfile(LOG_PATH), f"Missing auth.log file at {LOG_PATH}"
    with open(LOG_PATH, "r", encoding="utf-8") as handle:
        assert handle.read() == CANONICAL_LOG, "The provided authentication log was modified"


def test_certificates():
    ca_key = "/home/user/certs/ca.key"
    ca_crt = "/home/user/certs/ca.crt"
    server_key = "/home/user/certs/server.key"
    server_crt = "/home/user/certs/server.crt"

    for path in (ca_key, ca_crt, server_key, server_crt):
        assert os.path.isfile(path), f"Missing required certificate artifact: {path}"

    verify = run(["openssl", "verify", "-CAfile", ca_crt, server_crt])
    assert verify.returncode == 0 and "OK" in verify.stdout, verify.stdout + verify.stderr

    subject = openssl("x509", "-in", server_crt, "-noout", "-subject")
    assert "CN = secure.localnet" in subject or "CN=secure.localnet" in subject, subject

    for key in (ca_key, server_key):
        key_text = openssl("pkey", "-in", key, "-noout", "-text")
        assert re.search(r"Private-Key:\s*\(2048 bit", key_text), f"{key} is not an RSA-2048 private key"
        assert "modulus:" in key_text.lower(), f"{key} is not an RSA private key"

    assert openssl("pkey", "-in", ca_key, "-pubout") == openssl("x509", "-in", ca_crt, "-pubkey", "-noout"), \
        "ca.key does not match ca.crt"
    assert openssl("pkey", "-in", server_key, "-pubout") == openssl("x509", "-in", server_crt, "-pubkey", "-noout"), \
        "server.key does not match server.crt"

    ca_subject = cert_field(ca_crt, "subject")
    assert cert_field(ca_crt, "issuer") == ca_subject, "Root CA is not self-issued"
    assert cert_field(server_crt, "issuer") == ca_subject, "Server certificate was not issued by the Root CA"

    ca_verify = run(["openssl", "verify", "-CAfile", ca_crt, ca_crt])
    assert ca_verify.returncode == 0 and "OK" in ca_verify.stdout, "Root CA self-verification failed"
    ca_text = openssl("x509", "-in", ca_crt, "-noout", "-text")
    assert re.search(r"Basic Constraints:.*?CA:TRUE", ca_text, re.S), "Root certificate is not marked as a CA"

    now = datetime.datetime.now(datetime.timezone.utc)
    for path in (ca_crt, server_crt):
        not_before, not_after = cert_dates(path)
        duration = (not_after - not_before).total_seconds()
        assert abs(duration - 365 * 86400) <= 300, f"{path} is not valid for 365 days"
        assert not_before <= now <= not_after, f"{path} is not currently valid"


def test_jwt_generation_script_and_token():
    scripts = python_scripts()
    assert scripts, "No Python scripts were created under /home/user"
    candidates = [path for path in scripts if uses_pyjwt_encode(path)]
    assert candidates, "No Python script using PyJWT encode was found"

    successful = None
    for path in candidates:
        try:
            os.unlink(TOKEN_PATH)
        except FileNotFoundError:
            pass
        result = execute_script(path)
        if result is None or result.returncode != 0:
            continue
        try:
            read_and_validate_token()
            successful = path
            break
        except AssertionError:
            continue

    assert successful is not None, "No PyJWT generation script produced the required new_token.txt"
    read_and_validate_token()


def test_blocked_ip_parser_script_on_unseen_log_and_original_log():
    scripts = python_scripts()
    assert scripts, "No Python scripts were created under /home/user"

    marker = secrets.token_hex(12)
    octet = secrets.randbelow(200) + 20
    ip_ten = f"10.{octet}.0.10"
    ip_two = f"10.{octet}.0.2"
    ip_other = f"172.20.{secrets.randbelow(200) + 20}.7"
    expected_dynamic = sorted({ip_ten, ip_two, ip_other}, key=ipaddress.ip_address)

    challenge_lines = [
        f"[2026-01-01 00:00:04] IP: {ip_ten} Token: {make_test_token({'malicious': True, 'marker': marker})}",
        f"[2026-01-01 00:00:01] IP: 192.0.2.9 Token: {make_test_token({'malicious': False, 'marker': marker})}",
        f"[2026-01-01 00:00:02] IP: {ip_two} Token: {make_test_token({'malicious': True, 'marker': marker})}",
        f"[2026-01-01 00:00:03] IP: {ip_other} Token: {make_test_token({'malicious': True, 'marker': marker})}",
        f"[2026-01-01 00:00:05] IP: {ip_ten} Token: {make_test_token({'malicious': True, 'marker': marker})}",
        f"[2026-01-01 00:00:06] IP: 198.51.100.4 Token: {make_test_token({'malicious': 'true', 'marker': marker})}",
        "[2026-01-01 00:00:07] IP: 203.0.113.8 Token: not.a.valid.jwt",
    ]
    challenge = "\n".join(challenge_lines) + "\n"

    selected = None
    try:
        for path in scripts:
            with open(LOG_PATH, "w", encoding="utf-8") as handle:
                handle.write(challenge)
            try:
                os.unlink(BLOCKED_PATH)
            except FileNotFoundError:
                pass

            result = execute_script(path)
            if result is None or result.returncode != 0:
                continue
            try:
                if read_blocked() == expected_dynamic:
                    selected = path
                    break
            except AssertionError:
                pass
    finally:
        with open(LOG_PATH, "w", encoding="utf-8") as handle:
            handle.write(CANONICAL_LOG)

    assert selected is not None, "No Python parser produced correct blocked IPs for an unseen authentication log"

    try:
        os.unlink(BLOCKED_PATH)
    except FileNotFoundError:
        pass
    result = execute_script(selected)
    assert result is not None and result.returncode == 0, "The parser failed on the provided authentication log"

    with open(LOG_PATH, "r", encoding="utf-8") as handle:
        assert handle.read() == CANONICAL_LOG, "The parser modified the authentication log"

    expected_sorted = expected_from_log(LOG_PATH)
    assert expected_sorted == ["10.0.5.55", "192.168.100.2"]
    actual_ips = read_blocked()
    assert actual_ips == expected_sorted, \
        f"Contents of {BLOCKED_PATH} are incorrect. Expected: {expected_sorted}; got: {actual_ips}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
