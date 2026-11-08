#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import base64
import secrets
import string
import subprocess
import tempfile
import urllib.parse
import pytest

OLD_KEY = "0LDS3cR3T_123456"
NEW_KEY = "N3wS3cur3K3y9988"
SOURCE = "/home/user/auth_server/login_handler_patched.cpp"
BINARY = "/home/user/auth_server/login_handler_patched.cgi"
ORIGINAL_BINARY = "/home/user/auth_server/login_handler.cgi"


def compute_signature(key: str, data: str) -> str:
    hash_val = 0
    input_str = key + data
    for c in input_str:
        hash_val = (hash_val * 31) + ord(c)
        hash_val &= 0xFFFFFFFF
    return f"{hash_val:08x}"


def encode_payload(value: str) -> str:
    return base64.b64encode(value.encode()).decode().rstrip("=")


def execute(binary: str, query_string=None):
    env = os.environ.copy()
    if query_string is None:
        env.pop("QUERY_STRING", None)
    else:
        env["QUERY_STRING"] = query_string
    try:
        return subprocess.run(
            [binary], env=env, capture_output=True, timeout=2, check=False
        )
    except Exception as exc:
        pytest.fail(f"Failed to execute {binary}: {exc}")


def query_for(target: str, key: str = NEW_KEY):
    payload = encode_payload(target)
    signature = compute_signature(key, payload)
    return payload, f"payload={payload}&signature={signature}"


def location_lines(stdout: bytes):
    return [line.decode("utf-8", "replace") for line in stdout.splitlines()
            if line.startswith(b"Location: ")]


def assert_redirect(binary: str, target: str, expected: str):
    _, qs = query_for(target)
    result = execute(binary, qs)
    assert result.returncode == 0, f"CGI exited with {result.returncode}: {result.stderr!r}"
    locations = location_lines(result.stdout)
    assert locations == [f"Location: {expected}"], (
        f"Expected exactly one Location header for {expected!r}, got {locations!r}; "
        f"stdout={result.stdout!r}"
    )


def assert_rejected(binary: str, qs: str):
    result = execute(binary, qs)
    assert result.returncode == 0, f"CGI exited with {result.returncode}: {result.stderr!r}"
    assert location_lines(result.stdout) == [], (
        f"Rejected request emitted a Location header: {result.stdout!r}"
    )
    assert b"Invalid Signature!" in result.stdout, (
        f"Rejected request did not report an invalid signature: {result.stdout!r}"
    )


def test_phase1_old_key():
    path = "/home/user/old_key.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        raw = f.read()
    content = raw.strip()
    assert content == OLD_KEY, f"The extracted old key in {path} is incorrect."
    assert raw == OLD_KEY, f"{path} contains trailing or leading whitespace."


def test_phase1_exploit_qs():
    path = "/home/user/exploit_qs.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        raw = f.read()
    qs = raw.strip()
    assert raw == qs, f"{path} contains trailing or leading whitespace."

    parsed = urllib.parse.parse_qs(qs, keep_blank_values=True)
    assert "payload" in parsed, "Exploit query string missing 'payload' parameter."
    assert "signature" in parsed, "Exploit query string missing 'signature' parameter."

    payload = parsed["payload"][0]
    signature = parsed["signature"][0]
    try:
        decoded_url = base64.b64decode(payload).decode("utf-8")
    except Exception:
        pytest.fail("Payload is not valid base64.")

    assert decoded_url == "http://attacker.com/steal", f"Decoded payload URL is '{decoded_url}', expected 'http://attacker.com/steal'."
    expected_sig = compute_signature(OLD_KEY, payload)
    assert signature == expected_sig, f"Signature in exploit query string is incorrect. Expected {expected_sig}, got {signature}."

    result = execute(ORIGINAL_BINARY, qs)
    assert result.returncode == 0, f"Original CGI exited with {result.returncode}."
    assert location_lines(result.stdout) == ["Location: http://attacker.com/steal"], (
        f"The saved PoC does not demonstrate the redirect against the original CGI: {result.stdout!r}"
    )


def test_phase2_patched_cpp_exists():
    path = SOURCE
    assert os.path.isfile(path), f"Patched source file {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "extern const char* SECRET_KEY;" not in content, "The extern declaration for SECRET_KEY was not removed."
    assert NEW_KEY in content, "The new secret key is not hardcoded in the patched source file."
    assert re.search(r"\bconst\s+std::string\s+SECRET_KEY\s*(?:=|\{|\()", content), (
        "The patched source does not define SECRET_KEY as a const std::string."
    )


def test_phase2_patched_cgi_exists():
    path = BINARY
    assert os.path.isfile(path), f"Compiled patched CGI {path} is missing."
    assert os.access(path, os.X_OK), f"Compiled patched CGI {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled patched CGI {path} is not a Linux ELF executable."


def run_cgi(payload_str: str) -> str:
    payload_b64 = base64.b64encode(payload_str.encode()).decode("utf-8")
    payload_b64 = payload_b64.rstrip("=")
    signature = compute_signature(NEW_KEY, payload_b64)
    qs = f"payload={payload_b64}&signature={signature}"
    result = execute(BINARY, qs)
    return result.stdout.decode("utf-8", "replace")


def test_phase2_patched_cgi_valid_redirect():
    target = "/dashboard"
    stdout = run_cgi(target)
    assert "Location: /dashboard" in stdout, "Valid relative redirect failed to output the correct Location header."
    assert location_lines(stdout.encode()) == ["Location: /dashboard"]


def test_phase2_patched_cgi_malicious_redirect_absolute():
    target = "http://attacker.com/steal"
    stdout = run_cgi(target)
    assert "Location: /home" in stdout, "Absolute URL redirect was not defaulted to /home."
    assert location_lines(stdout.encode()) == ["Location: /home"]


def test_phase2_patched_cgi_malicious_redirect_protocol_relative():
    target = "//attacker.com/steal"
    stdout = run_cgi(target)
    assert "Location: /home" in stdout, "Protocol-relative URL redirect (//...) was not defaulted to /home."
    assert location_lines(stdout.encode()) == ["Location: /home"]


def test_phase2_patched_cgi_malicious_redirect_no_slash():
    target = "dashboard"
    stdout = run_cgi(target)
    assert "Location: /home" in stdout, "Relative URL not starting with a slash was not defaulted to /home."
    assert location_lines(stdout.encode()) == ["Location: /home"]


@pytest.fixture(scope="session")
def rebuilt_binary():
    directory = tempfile.mkdtemp(prefix="patched-build-")
    output = os.path.join(directory, "login_handler_patched.cgi")
    result = subprocess.run(
        ["g++", "-std=c++11", SOURCE, "-o", output],
        capture_output=True, timeout=20, check=False
    )
    assert result.returncode == 0, (
        "The submitted patched source does not independently compile with g++ -std=c++11:\n"
        + result.stderr.decode("utf-8", "replace")
    )
    with open(output, "rb") as f:
        assert f.read(4) == b"\x7fELF"
    return output


def test_randomized_behavior_and_signature_verification(rebuilt_binary):
    alphabet = string.ascii_letters + string.digits
    nonce = "".join(secrets.choice(alphabet) for _ in range(24))
    safe_targets = [
        "/",
        f"/{nonce}",
        f"/account/{nonce}/settings?tab={nonce[:8]}",
    ]
    unsafe_targets = [
        f"http://{nonce}.example/steal",
        f"https://{nonce}.example/steal",
        f"//{nonce}.example/steal",
        nonce,
        "",
    ]

    for binary in (BINARY, rebuilt_binary):
        for target in safe_targets:
            assert_redirect(binary, target, target)
        for target in unsafe_targets:
            assert_redirect(binary, target, "/home")

        payload = encode_payload(f"/{nonce}/signed")
        correct = compute_signature(NEW_KEY, payload)
        wrong = ("0" if correct[0] != "0" else "1") + correct[1:]
        assert_rejected(binary, f"payload={payload}&signature={wrong}")

        old_signature = compute_signature(OLD_KEY, payload)
        if old_signature == correct:
            payload = encode_payload(f"/{nonce}/signed-again")
            old_signature = compute_signature(OLD_KEY, payload)
            assert old_signature != compute_signature(NEW_KEY, payload)
        assert_rejected(binary, f"payload={payload}&signature={old_signature}")

        other_payload = encode_payload(f"/{nonce}/other")
        assert_rejected(binary, f"payload={other_payload}&signature={correct}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
