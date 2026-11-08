#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest


def test_invalid_sessions_enc_exists():
    """Check that the final encrypted file exists."""
    assert os.path.isfile("/home/user/invalid_sessions.enc"), (
        "The file /home/user/invalid_sessions.enc is missing. "
        "Did you forget to encrypt the results?"
    )


def test_invalid_sessions_enc_content():
    """Decrypt the results and verify the invalid sessions are correctly logged."""
    enc_path = "/home/user/invalid_sessions.enc"
    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
        "-in", enc_path,
        "-pass", "pass:audit_pass_2024"
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(
            "Failed to decrypt /home/user/invalid_sessions.enc. Ensure it was "
            "encrypted with aes-256-cbc, -pbkdf2, and the correct password.\n"
            f"OpenSSL error: {e.stderr}"
        )

    decrypted_content = result.stdout.strip().splitlines()
    expected_lines = [
        "SESSION_ID: SESS-1002 | IP: 10.0.0.51",
        "SESSION_ID: SESS-1004 | IP: 192.168.1.105"
    ]

    assert len(decrypted_content) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in the decrypted log, "
        f"but found {len(decrypted_content)}."
    )
    for expected in expected_lines:
        assert expected in decrypted_content, (
            f"Expected line '{expected}' not found in the decrypted output. "
            f"Actual output:\n{result.stdout}"
        )


def _is_decrypted_log(path):
    try:
        if not path.is_file() or path.stat().st_size > 5_000_000:
            return False
        lines = [line for line in path.read_text().splitlines() if line.strip()]
        if not lines:
            return False
        records = [json.loads(line) for line in lines]
        return all(
            isinstance(record, dict)
            and {"session_id", "client_ip", "client_cert_pem"} <= set(record)
            for record in records
        )
    except (OSError, UnicodeError, json.JSONDecodeError):
        return False


def test_rust_program_validates_certificates_on_fresh_input():
    project = Path("/home/user/audit")
    manifest = project / "Cargo.toml"
    source = project / "src/main.rs"
    assert project.is_dir(), "/home/user/audit is not a Cargo project directory"
    assert manifest.is_file(), "/home/user/audit/Cargo.toml is missing"
    assert source.is_file(), "/home/user/audit/src/main.rs is missing"
    assert source.read_text().strip(), "/home/user/audit/src/main.rs is empty"

    ca_path = Path("/home/user/ca.pem")
    enc_path = Path("/home/user/logs.enc")
    output_log = Path("/home/user/invalid_sessions.log")
    output_enc = Path("/home/user/invalid_sessions.enc")
    fixed_paths = [ca_path, enc_path, output_log, output_enc]
    fixed_backups = {p: p.read_bytes() if p.exists() else None for p in fixed_paths}
    input_backups = {}

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)

        def run(*args):
            return subprocess.run(
                list(args), cwd=td, capture_output=True, text=True,
                check=True, timeout=60
            )

        run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", "test-ca.key", "-out", "test-ca.pem", "-days", "30",
            "-subj", "/CN=VerifierDynamicCA")
        run("openssl", "req", "-newkey", "rsa:2048", "-nodes",
            "-keyout", "valid.key", "-out", "valid.csr",
            "-subj", "/CN=DynamicValidClient")
        run("openssl", "x509", "-req", "-in", "valid.csr",
            "-CA", "test-ca.pem", "-CAkey", "test-ca.key", "-CAcreateserial",
            "-out", "valid.pem", "-days", "30")
        run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", "invalid.key", "-out", "invalid.pem", "-days", "30",
            "-subj", "/CN=DynamicRogueClient")

        valid_pem = (td / "valid.pem").read_text()
        invalid_pem = (td / "invalid.pem").read_text()
        token = uuid.uuid4().hex
        valid_id = "DYN-VALID-" + token
        invalid_id = "DYN-INVALID-" + token
        valid_ip = "198.51.100.17"
        invalid_ip = "203.0.113.29"
        records = [
            {"session_id": valid_id, "client_ip": valid_ip,
             "client_cert_pem": valid_pem},
            {"session_id": invalid_id, "client_ip": invalid_ip,
             "client_cert_pem": invalid_pem},
        ]
        payload = "".join(json.dumps(record) + "\n" for record in records)
        plain = td / "dynamic_logs.json"
        plain.write_text(payload)
        run("openssl", "enc", "-aes-256-cbc", "-pbkdf2",
            "-in", str(plain), "-out", "dynamic_logs.enc",
            "-pass", "pass:audit_pass_2024")

        candidates = set()
        for path in Path("/home/user").rglob("*"):
            if path not in fixed_paths and _is_decrypted_log(path):
                candidates.add(path)
        for path in [
            Path("/home/user/logs.json"),
            Path("/home/user/decrypted_logs.json"),
            Path("/home/user/logs_decrypted.json"),
            Path("/home/user/decrypted_logs.log"),
            project / "logs.json",
            project / "decrypted_logs.json",
            project / "logs_decrypted.json",
        ]:
            if not path.exists() or path.is_file():
                candidates.add(path)

        try:
            ca_path.write_bytes((td / "test-ca.pem").read_bytes())
            enc_path.write_bytes((td / "dynamic_logs.enc").read_bytes())
            for path in candidates:
                input_backups[path] = path.read_bytes() if path.exists() else None
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(payload)
            output_log.unlink(missing_ok=True)
            output_enc.unlink(missing_ok=True)

            result = subprocess.run(
                ["cargo", "run", "--quiet"],
                cwd=project, capture_output=True, text=True, timeout=180
            )
            assert result.returncode == 0, (
                "The Cargo project failed when executed on fresh audit data.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert output_log.is_file(), (
                "The Rust program did not generate /home/user/invalid_sessions.log"
            )
            actual = output_log.read_text().strip().splitlines()
            expected = [f"SESSION_ID: {invalid_id} | IP: {invalid_ip}"]
            assert actual == expected, (
                "The Rust program did not classify fresh certificates correctly. "
                f"Expected {expected!r}, got {actual!r}"
            )
        finally:
            for path, data in input_backups.items():
                if data is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_bytes(data)
            for path, data in fixed_backups.items():
                if data is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_bytes(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
