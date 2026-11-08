#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import secrets
import shlex
import stat
import subprocess
import hmac
import hashlib

KEYS_DIR = "/home/user/app/keys"
CA_CRT = os.path.join(KEYS_DIR, "ca.crt")
CA_KEY = os.path.join(KEYS_DIR, "ca.key")
SERVER_CRT = os.path.join(KEYS_DIR, "server.crt")
SERVER_KEY = os.path.join(KEYS_DIR, "server.key")
VALIDATE_SCRIPT = "/home/user/app/validate_jwt.py"
FIREWALL_SCRIPT = "/home/user/app/firewall.sh"


def _run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, **kwargs)


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _jwt_parts(algorithm: str, payload: dict):
    header = _b64(json.dumps({"alg": algorithm, "typ": "JWT"}, separators=(",", ":")).encode())
    body = _b64(json.dumps(payload, separators=(",", ":")).encode())
    return header, body, f"{header}.{body}"


def _sign_rsa(message: str, digest: str = "sha256") -> str:
    result = _run(["openssl", "dgst", f"-{digest}", "-sign", SERVER_KEY], input=message.encode())
    assert result.returncode == 0, f"Failed to sign test token: {result.stderr.decode(errors='replace')}"
    return _b64(result.stdout)


def _run_validate_script(token: str) -> str:
    cmd = ["python3", VALIDATE_SCRIPT]
    result = subprocess.run(cmd, input=token, capture_output=True, text=True)
    return result.stdout.strip()


def _key_bits(path: str) -> int:
    result = _run(["openssl", "pkey", "-in", path, "-text", "-noout"], text=True)
    assert result.returncode == 0, f"{path} is not a readable private key: {result.stderr}"
    match = re.search(r"Private-Key:\s*\((\d+) bit", result.stdout)
    assert match, f"Could not determine RSA key size for {path}"
    assert "RSA" in result.stdout or "modulus:" in result.stdout, f"{path} is not an RSA private key"
    return int(match.group(1))


def _private_public_der(path: str) -> bytes:
    result = _run(["openssl", "pkey", "-in", path, "-pubout", "-outform", "DER"])
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return result.stdout


def _certificate_public_der(path: str) -> bytes:
    first = _run(["openssl", "x509", "-in", path, "-pubkey", "-noout"])
    assert first.returncode == 0, first.stderr.decode(errors="replace")
    second = _run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=first.stdout)
    assert second.returncode == 0, second.stderr.decode(errors="replace")
    return second.stdout


def test_keys_and_permissions():
    """Check that all required material exists and server.key has 400 permissions."""
    assert os.path.exists(CA_CRT), f"Missing {CA_CRT}"
    assert os.path.exists(CA_KEY), f"Missing {CA_KEY}"
    assert os.path.exists(SERVER_CRT), f"Missing {SERVER_CRT}"
    assert os.path.exists(SERVER_KEY), f"Missing {SERVER_KEY}"
    for path in (CA_CRT, CA_KEY, SERVER_CRT, SERVER_KEY):
        assert os.path.isfile(path), f"{path} is not a regular file"

    st = os.stat(SERVER_KEY)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Permissions of {SERVER_KEY} are {oct(perms)}, expected 0o400"

    assert _key_bits(CA_KEY) == 2048, "ca.key must be a 2048-bit RSA key"
    assert _key_bits(SERVER_KEY) == 2048, "server.key must be a 2048-bit RSA key"
    assert _private_public_der(CA_KEY) == _certificate_public_der(CA_CRT), "ca.key does not match ca.crt"
    assert _private_public_der(SERVER_KEY) == _certificate_public_der(SERVER_CRT), "server.key does not match server.crt"


def test_certificate_chain():
    """Verify that server.crt is signed by ca.crt."""
    cmd = ["openssl", "verify", "-CAfile", CA_CRT, SERVER_CRT]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Certificate verification failed: {result.stderr}"
    assert "OK" in result.stdout, "Certificate verification output does not contain 'OK'"


def test_jwt_validation_none_alg():
    """Test that validate_jwt.py rejects an alg=none token."""
    assert os.path.isfile(VALIDATE_SCRIPT), f"Missing {VALIDATE_SCRIPT}"
    payload = {"sub": secrets.token_hex(12), "nonce": secrets.token_hex(16)}
    header, body, _ = _jwt_parts("none", payload)
    token = f"{header}.{body}."
    output = _run_validate_script(token)
    assert output == "INVALID", f"Expected INVALID for none alg token, got {output}"


def test_jwt_validation_valid_rs256():
    """Test several freshly generated, correctly signed RS256 tokens."""
    for _ in range(3):
        payload = {"sub": secrets.token_hex(12), "nonce": secrets.token_hex(24)}
        _, _, message = _jwt_parts("RS256", payload)
        token = f"{message}.{_sign_rsa(message)}"
        output = _run_validate_script(token)
        assert output == "VALID", f"Expected VALID for correctly signed RS256 token, got {output}"


def test_jwt_rejects_bad_rs256_signatures_and_tampering():
    payload = {"sub": secrets.token_hex(12), "nonce": secrets.token_hex(24)}
    header, body, message = _jwt_parts("RS256", payload)
    signature = _sign_rsa(message)

    bad_signature = _b64(os.urandom(256))
    assert _run_validate_script(f"{message}.{bad_signature}") == "INVALID"

    changed_body = _b64(json.dumps({"sub": payload["sub"], "nonce": secrets.token_hex(24)}, separators=(",", ":")).encode())
    assert changed_body != body
    assert _run_validate_script(f"{header}.{changed_body}.{signature}") == "INVALID"


def test_jwt_rejects_symmetric_and_non_rs256_algorithms():
    payload = {"sub": secrets.token_hex(12), "nonce": secrets.token_hex(24)}

    header, body, message = _jwt_parts("HS256", payload)
    secret = os.urandom(32)
    hs_signature = _b64(hmac.new(secret, message.encode(), hashlib.sha256).digest())
    assert _run_validate_script(f"{message}.{hs_signature}") == "INVALID"

    _, _, rs384_message = _jwt_parts("RS384", payload)
    rs384_token = f"{rs384_message}.{_sign_rsa(rs384_message, 'sha384')}"
    assert _run_validate_script(rs384_token) == "INVALID"

    assert _run_validate_script(secrets.token_urlsafe(40)) == "INVALID"


def _direct_iptables_commands(content: str):
    commands = []
    for line_number, line in enumerate(content.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            words = shlex.split(stripped, comments=True, posix=True)
        except ValueError as exc:
            raise AssertionError(f"Invalid shell syntax on firewall.sh line {line_number}: {exc}")
        if words and words[0] == "sudo":
            words = words[1:]
        if words and os.path.basename(words[0]) == "iptables":
            commands.append((line_number, words[1:]))
    return commands


def _has_option(args, option, value):
    return any(args[i] == option and i + 1 < len(args) and args[i + 1] == value for i in range(len(args)))


def test_firewall_script():
    """Verify required rules are actual shell commands, not comments or string literals."""
    assert os.path.exists(FIREWALL_SCRIPT), f"Missing {FIREWALL_SCRIPT}"
    assert os.path.isfile(FIREWALL_SCRIPT), f"{FIREWALL_SCRIPT} is not a regular file"
    with open(FIREWALL_SCRIPT, "r") as f:
        content = f.read()

    # Preserve the original content assertions.
    assert re.search(r"iptables\s+-A\s+INPUT\s+.*-p\s+tcp\s+.*-s\s+127\.0\.0\.1\s+.*--dport\s+8000\s+.*-j\s+ACCEPT", content) or \
           re.search(r"iptables\s+-A\s+INPUT\s+.*-s\s+127\.0\.0\.1\s+.*-p\s+tcp\s+.*--dport\s+8000\s+.*-j\s+ACCEPT", content), \
           "Firewall script missing correct ACCEPT rule for 127.0.0.1 on port 8000"
    assert re.search(r"iptables\s+-A\s+INPUT\s+.*-p\s+tcp\s+.*--dport\s+8000\s+.*-j\s+DROP", content), \
           "Firewall script missing correct DROP rule for port 8000"

    syntax = subprocess.run(["bash", "-n", FIREWALL_SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"firewall.sh has invalid shell syntax: {syntax.stderr}"

    commands = _direct_iptables_commands(content)
    accept_lines = []
    drop_lines = []
    for line_number, args in commands:
        base = (_has_option(args, "-A", "INPUT") and
                _has_option(args, "-p", "tcp") and
                _has_option(args, "--dport", "8000"))
        if base and _has_option(args, "-s", "127.0.0.1") and _has_option(args, "-j", "ACCEPT"):
            accept_lines.append(line_number)
        if base and _has_option(args, "-j", "DROP"):
            sources = [args[i + 1] for i, item in enumerate(args[:-1]) if item in ("-s", "--source")]
            if not sources or all(source in ("0.0.0.0/0", "0/0") for source in sources):
                drop_lines.append(line_number)

    assert accept_lines, "Required ACCEPT rule must appear as an actual iptables command"
    assert drop_lines, "Required DROP rule must appear as an actual iptables command"
    assert min(accept_lines) < min(drop_lines), "The localhost ACCEPT rule must precede the catch-all DROP rule"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
