#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import secrets
import subprocess

import pytest
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

PROJECT_PATH = pathlib.Path("/home/user/decryptor")
PARAMS_PATH = pathlib.Path("/home/user/incident_workspace/crypto_params.txt")
WEB_ENC_PATH = pathlib.Path("/home/user/incident_workspace/encrypted/web.log.enc")
AUTH_ENC_PATH = pathlib.Path("/home/user/incident_workspace/encrypted/auth.log.enc")
WEB_LOG_PATH = pathlib.Path("/home/user/incident_workspace/decrypted/web.log")
AUTH_LOG_PATH = pathlib.Path("/home/user/incident_workspace/decrypted/auth.log")
REPORT_PATH = "/home/user/incident_report.json"


def parse_params(data):
    lines = data.decode("ascii").splitlines()
    assert len(lines) == 2, "crypto_params.txt must contain exactly two lines"
    key = bytes.fromhex(lines[0])
    nonce = bytes.fromhex(lines[1])
    assert len(key) == 32, "The AES-256 key must be 32 bytes"
    assert len(nonce) == 12, "The GCM nonce must be 12 bytes"
    return key, nonce


def run_decryptor():
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["CARGO_HOME"] = "/home/user/.cargo"
    return subprocess.run(
        ["/usr/bin/cargo", "run", "--quiet", "--manifest-path", str(PROJECT_PATH / "Cargo.toml")],
        cwd=str(PROJECT_PATH),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
        check=False,
    )


def remove_outputs():
    for path in (WEB_LOG_PATH, AUTH_LOG_PATH):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def test_00_rust_decryptor_executes_and_decrypts_aes256_gcm():
    assert PROJECT_PATH.is_dir(), f"Rust project not found at {PROJECT_PATH}"
    assert (PROJECT_PATH / "Cargo.toml").is_file(), "decryptor is missing Cargo.toml"
    assert (PROJECT_PATH / "src" / "main.rs").is_file(), "decryptor is missing src/main.rs"

    metadata = subprocess.run(
        ["/usr/bin/cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", str(PROJECT_PATH / "Cargo.toml")],
        cwd=str(PROJECT_PATH),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        check=False,
    )
    assert metadata.returncode == 0, f"Invalid Rust project: {metadata.stderr}"
    cargo_data = json.loads(metadata.stdout)
    project_root = PROJECT_PATH.resolve()
    rust_bins = []
    for package in cargo_data.get("packages", []):
        for target in package.get("targets", []):
            src = pathlib.Path(target.get("src_path", ""))
            if "bin" in target.get("kind", []) and src.suffix == ".rs":
                try:
                    src.resolve().relative_to(project_root)
                    rust_bins.append(src)
                except ValueError:
                    pass
    assert rust_bins, "Cargo project does not define a Rust binary target inside /home/user/decryptor"

    original_params = PARAMS_PATH.read_bytes()
    original_web_enc = WEB_ENC_PATH.read_bytes()
    original_auth_enc = AUTH_ENC_PATH.read_bytes()
    original_key, original_nonce = parse_params(original_params)
    original_aes = AESGCM(original_key)
    expected_original_web = original_aes.decrypt(original_nonce, original_web_enc, None)
    expected_original_auth = original_aes.decrypt(original_nonce, original_auth_enc, None)

    dynamic_error = None
    try:
        key = secrets.token_bytes(32)
        nonce = secrets.token_bytes(12)
        expected_web = b"dynamic-web-log:" + secrets.token_bytes(97) + b"\n"
        expected_auth = b"dynamic-auth-log:" + secrets.token_bytes(113) + b"\n"
        aes = AESGCM(key)

        PARAMS_PATH.write_text(key.hex() + "\n" + nonce.hex() + "\n", encoding="ascii")
        WEB_ENC_PATH.write_bytes(aes.encrypt(nonce, expected_web, None))
        AUTH_ENC_PATH.write_bytes(aes.encrypt(nonce, expected_auth, None))
        remove_outputs()

        result = run_decryptor()
        assert result.returncode == 0, f"decryptor failed on a generated AES-256-GCM test vector: {result.stderr.decode(errors='replace')}"
        assert WEB_LOG_PATH.is_file(), "decryptor did not create decrypted/web.log"
        assert AUTH_LOG_PATH.is_file(), "decryptor did not create decrypted/auth.log"
        assert WEB_LOG_PATH.read_bytes() == expected_web, "web.log was not correctly decrypted from the generated test vector"
        assert AUTH_LOG_PATH.read_bytes() == expected_auth, "auth.log was not correctly decrypted from the generated test vector"
    except BaseException as exc:
        dynamic_error = exc
    finally:
        PARAMS_PATH.write_bytes(original_params)
        WEB_ENC_PATH.write_bytes(original_web_enc)
        AUTH_ENC_PATH.write_bytes(original_auth_enc)

    remove_outputs()
    result = run_decryptor()
    assert result.returncode == 0, f"decryptor failed on the supplied incident logs: {result.stderr.decode(errors='replace')}"
    assert WEB_LOG_PATH.is_file(), "decryptor did not recreate decrypted/web.log"
    assert AUTH_LOG_PATH.is_file(), "decryptor did not recreate decrypted/auth.log"
    assert WEB_LOG_PATH.read_bytes() == expected_original_web, "decrypted web.log does not exactly match the supplied ciphertext"
    assert AUTH_LOG_PATH.read_bytes() == expected_original_auth, "decrypted auth.log does not exactly match the supplied ciphertext"

    if dynamic_error is not None:
        raise dynamic_error


def test_decrypted_web_log_exists_and_correct():
    assert os.path.isfile(WEB_LOG_PATH), f"Decrypted web log not found at {WEB_LOG_PATH}"

    with open(WEB_LOG_PATH, "r") as f:
        content = f.read()

    assert "192.168.1.105 - GET /api/v1/diagnostic" in content, "Decrypted web log does not contain the expected attacker traffic. Decryption may have failed or output is incorrect."
    assert "10.0.0.55 - GET /index.html 200" in content, "Decrypted web log is missing expected benign traffic."


def test_decrypted_auth_log_exists_and_correct():
    assert os.path.isfile(AUTH_LOG_PATH), f"Decrypted auth log not found at {AUTH_LOG_PATH}"

    with open(AUTH_LOG_PATH, "r") as f:
        content = f.read()

    assert "COMMAND=/usr/bin/tar -cf /dev/null" in content, "Decrypted auth log does not contain the expected privilege escalation event."
    assert "Accepted publickey for user1" in content, "Decrypted auth log is missing expected benign events."


def test_incident_report_exists_and_valid_json():
    assert os.path.isfile(REPORT_PATH), f"Incident report not found at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Incident report is not valid JSON.")

    assert isinstance(report, dict), "Incident report should be a JSON object."

    expected_keys = {"attacker_ip", "exploited_endpoint", "privesc_binary"}
    assert expected_keys.issubset(report.keys()), f"Incident report is missing required keys. Expected {expected_keys}, found {set(report.keys())}"


def test_incident_report_values():
    with open(REPORT_PATH, "r") as f:
        report = json.load(f)

    assert report.get("attacker_ip") == "192.168.1.105", f"Incorrect attacker_ip. Expected '192.168.1.105', got '{report.get('attacker_ip')}'"
    assert report.get("exploited_endpoint") == "/api/v1/diagnostic", f"Incorrect exploited_endpoint. Expected '/api/v1/diagnostic', got '{report.get('exploited_endpoint')}'"
    assert report.get("privesc_binary") == "/usr/bin/tar", f"Incorrect privesc_binary. Expected '/usr/bin/tar', got '{report.get('privesc_binary')}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
