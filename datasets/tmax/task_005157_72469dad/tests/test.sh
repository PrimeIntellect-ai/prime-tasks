#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_go_execution.py
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile

HOME = Path('/home/user')
AUTH = HOME / 'data/auth.log'
UFW = HOME / 'data/ufw.log'
SECRET = HOME / 'config/jwt.secret'
TOKEN = HOME / 'audit_token.txt'


def b64decode(value):
    return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))


def validate_token(expected_ips, secret):
    if not TOKEN.is_file():
        raise AssertionError('Go program did not create /home/user/audit_token.txt')
    raw = TOKEN.read_bytes()
    if not raw or raw != raw.strip() or any(chr(c).isspace() for c in raw):
        raise AssertionError('Token file contains surrounding or embedded whitespace')
    try:
        token = raw.decode('ascii')
    except UnicodeDecodeError as exc:
        raise AssertionError('Token is not ASCII') from exc
    parts = token.split('.')
    if len(parts) != 3:
        raise AssertionError('Token does not have exactly three parts')
    header_b64, payload_b64, signature_b64 = parts
    header = json.loads(b64decode(header_b64).decode('utf-8'))
    payload = json.loads(b64decode(payload_b64).decode('utf-8'))
    if header.get('alg') != 'HS256':
        raise AssertionError('Token is not HS256')
    message = (header_b64 + '.' + payload_b64).encode('ascii')
    expected_signature = base64.urlsafe_b64encode(
        hmac.new(secret.encode('utf-8'), message, hashlib.sha256).digest()
    ).decode('ascii').rstrip('=')
    if not hmac.compare_digest(signature_b64, expected_signature):
        raise AssertionError('Token signature is invalid')
    if payload.get('role') != 'compliance_analyst':
        raise AssertionError('Incorrect role claim')
    if payload.get('audited_ips') != expected_ips:
        raise AssertionError(
            f"Expected audited_ips {expected_ips}, got {payload.get('audited_ips')}"
        )


def source_directories():
    found = []
    for root, dirs, files in os.walk(HOME):
        rel = Path(root).relative_to(HOME)
        dirs[:] = [
            d for d in dirs
            if d not in {'.git', '.cache', 'pkg', 'vendor'}
            and not (rel == Path('.') and d == 'go')
        ]
        go_files = [name for name in files if name.endswith('.go') and not name.endswith('_test.go')]
        if not go_files:
            continue
        has_main = False
        for name in go_files:
            try:
                text = (Path(root) / name).read_text(errors='replace')
            except OSError:
                continue
            if re.search(r'^\s*package\s+main\s*$', text, re.MULTILINE):
                has_main = True
                break
        if has_main:
            found.append(Path(root))
    return sorted(set(found), key=lambda p: str(p))


def build_candidate(source_dir, output):
    base_env = os.environ.copy()
    base_env.update({
        'HOME': '/home/user',
        'GOPATH': '/home/user/go',
        'GOCACHE': '/tmp/go-build-cache',
    })
    attempts = [base_env, dict(base_env, GO111MODULE='off')]
    for env in attempts:
        result = subprocess.run(
            ['go', 'build', '-o', str(output), '.'],
            cwd=str(source_dir), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=90,
        )
        if result.returncode == 0 and output.is_file():
            return True
    return False


def write_challenge():
    a = f'198.51.100.{secrets.randbelow(180) + 20}'
    b = f'203.0.113.{secrets.randbelow(180) + 20}'
    failed_only = f'192.0.2.{secrets.randbelow(180) + 20}'
    blocked_only = f'10.23.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}'
    allowed = f'172.20.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}'
    secret = 'verification_' + secrets.token_hex(24)

    AUTH.write_text(
        f'2026-01-01T00:00:00Z ERR Failed login attempt user=a ip={b}\n'
        f'2026-01-01T00:00:01Z OK Successful login user=x ip={blocked_only}\n'
        f'2026-01-01T00:00:02Z ERR Failed login attempt user=b ip={failed_only}\n'
        f'2026-01-01T00:00:03Z ERR Failed login attempt user=c ip={a}\n'
        f'2026-01-01T00:00:04Z ERR Failed login attempt user=d ip={allowed}\n'
    )
    UFW.write_text(
        f'Jan  1 00:00:00 host kernel: [UFW BLOCK] IN=x SRC={a} DST=10.0.0.1 PROTO=TCP DPT=8080\n'
        f'Jan  1 00:00:01 host kernel: [UFW BLOCK] IN=x SRC={failed_only} DST=10.0.0.1 PROTO=TCP DPT=22\n'
        f'Jan  1 00:00:02 host kernel: [UFW ALLOW] IN=x SRC={allowed} DST=10.0.0.1 PROTO=TCP DPT=8080\n'
        f'Jan  1 00:00:03 host kernel: [UFW BLOCK] IN=x SRC={blocked_only} DST=10.0.0.1 PROTO=TCP DPT=8080\n'
        f'Jan  1 00:00:04 host kernel: [UFW BLOCK] IN=x SRC={b} DST=10.0.0.1 PROTO=TCP DPT=8080\n'
    )
    SECRET.write_text(secret)
    return sorted([a, b]), secret


def main():
    candidates = source_directories()
    if not candidates:
        raise AssertionError('No Go program with package main exists under /home/user')

    originals = {
        AUTH: AUTH.read_bytes(),
        UFW: UFW.read_bytes(),
        SECRET: SECRET.read_bytes(),
    }
    old_token = TOKEN.read_bytes() if TOKEN.is_file() else None
    temp_dir = Path(tempfile.mkdtemp(prefix='audit-go-verifier-'))
    successful_binary = None
    successful_cwd = None

    try:
        for index, source_dir in enumerate(candidates):
            binary = temp_dir / f'candidate-{index}'
            if not build_candidate(source_dir, binary):
                continue
            expected_ips, challenge_secret = write_challenge()
            try:
                TOKEN.unlink()
            except FileNotFoundError:
                pass
            result = subprocess.run(
                [str(binary)], cwd=str(source_dir),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=30,
            )
            if result.returncode != 0:
                continue
            try:
                validate_token(expected_ips, challenge_secret)
            except Exception:
                continue
            successful_binary = binary
            successful_cwd = source_dir
            break
    finally:
        for path, data in originals.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    if successful_binary is None:
        if old_token is None:
            try:
                TOKEN.unlink()
            except FileNotFoundError:
                pass
        else:
            TOKEN.write_bytes(old_token)
        shutil.rmtree(temp_dir, ignore_errors=True)
        raise AssertionError('No compiled Go program generated a correct token from fresh verifier inputs')

    try:
        try:
            TOKEN.unlink()
        except FileNotFoundError:
            pass
        result = subprocess.run(
            [str(successful_binary)], cwd=str(successful_cwd),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=30,
        )
        if result.returncode != 0:
            raise AssertionError('Go program failed when run against the original input files')
        if not TOKEN.is_file():
            raise AssertionError('Go program did not recreate the token for the original inputs')
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == '__main__':
    main()
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import base64
import hmac
import hashlib
import pytest

def decode_base64_url(s):
    padding = '=' * (4 - (len(s) % 4))
    return base64.urlsafe_b64decode(s + padding)

def verify_jwt(token, secret):
    parts = token.strip().split('.')
    if len(parts) != 3:
        return False, None, "Token does not have exactly 3 parts (header.payload.signature)"

    header_b64, payload_b64, signature_b64 = parts

    try:
        header = json.loads(decode_base64_url(header_b64).decode('utf-8'))
        if header.get('alg') != 'HS256':
            return False, None, f"Expected alg HS256, got {header.get('alg')}"
    except Exception as e:
        return False, None, f"Failed to parse header: {e}"

    message = f"{header_b64}.{payload_b64}".encode('utf-8')
    expected_sig = hmac.new(secret.encode('utf-8'), message, hashlib.sha256).digest()
    expected_sig_b64 = base64.urlsafe_b64encode(expected_sig).decode('utf-8').rstrip('=')

    if signature_b64 != expected_sig_b64:
        return False, None, "JWT signature verification failed"

    try:
        payload = json.loads(decode_base64_url(payload_b64).decode('utf-8'))
        return True, payload, "Success"
    except Exception as e:
        return False, None, f"Failed to parse payload: {e}"

def get_expected_ips():
    auth_ips = set()
    auth_log_path = "/home/user/data/auth.log"
    if os.path.isfile(auth_log_path):
        with open(auth_log_path, "r") as f:
            for line in f:
                if "Failed login attempt" in line:
                    match = re.search(r'ip=([^\s]+)', line)
                    if match:
                        auth_ips.add(match.group(1))

    ufw_ips = set()
    ufw_log_path = "/home/user/data/ufw.log"
    if os.path.isfile(ufw_log_path):
        with open(ufw_log_path, "r") as f:
            for line in f:
                if "[UFW BLOCK]" in line and "DPT=8080" in line:
                    match = re.search(r'SRC=([^\s]+)', line)
                    if match:
                        ufw_ips.add(match.group(1))

    return sorted(list(auth_ips.intersection(ufw_ips)))

def test_audit_token_exists():
    token_path = "/home/user/audit_token.txt"
    assert os.path.isfile(token_path), f"Expected token file {token_path} does not exist."

def test_audit_token_validity_and_claims():
    token_path = "/home/user/audit_token.txt"
    secret_path = "/home/user/config/jwt.secret"

    assert os.path.isfile(token_path), f"Token file {token_path} missing."
    assert os.path.isfile(secret_path), f"Secret file {secret_path} missing."

    with open(token_path, "r") as f:
        token = f.read()
    assert token != "", "Token file is empty"
    assert token == token.strip(), "Token file must not contain surrounding whitespace or newlines"
    assert not any(ch.isspace() for ch in token), "Token file must contain only the raw JWT"

    with open(secret_path, "r") as f:
        secret = f.read().strip()

    is_valid, payload, msg = verify_jwt(token, secret)
    assert is_valid, f"JWT validation failed: {msg}"

    assert payload is not None, "Payload could not be extracted from JWT"

    assert payload.get("role") == "compliance_analyst", \
        f"Expected role 'compliance_analyst', got {payload.get('role')}"

    expected_ips = get_expected_ips()
    audited_ips = payload.get("audited_ips")

    assert audited_ips is not None, "Claim 'audited_ips' is missing from JWT payload"
    assert isinstance(audited_ips, list), "'audited_ips' must be a JSON array"
    assert audited_ips == expected_ips, \
        f"Expected audited_ips to be {expected_ips}, but got {audited_ips}"
TEST_EOF

if python3 /tmp/verify_go_execution.py 2>&1 && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
