#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import subprocess

import pytest


def test_cracked_json_exists_and_correct():
    path = "/home/user/cracked.json"
    assert os.path.isfile(path), f"Expected file {path} does not exist. The student must output the cracked credentials to this file."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON. Ensure the output is properly formatted.")

    expected_data = {
        "alice": "sunshine",
        "charlie": "dragon"
    }

    assert data == expected_data, f"Contents of {path} do not match the expected cracked credentials. Expected {expected_data}, but got {data}."


def test_cargo_project_initialized():
    cargo_toml_path = "/home/user/cracker/Cargo.toml"
    assert os.path.isfile(cargo_toml_path), f"Expected Cargo project at /home/user/cracker, but {cargo_toml_path} does not exist."


def test_rust_cracker_processes_inputs_and_generates_report():
    paths = [
        "/home/user/auth.log",
        "/home/user/users.txt",
        "/home/user/wordlist.txt",
        "/home/user/cracked.json",
    ]
    backups = {path: open(path, "rb").read() if os.path.exists(path) else None for path in paths}

    pepper = "S3cr3tP3pp3r2024"
    mallory_password = "audit_" + secrets.token_hex(8)
    trent_password = "audit_" + secrets.token_hex(8)
    relative_password = "audit_" + secrets.token_hex(8)
    failed_password = "audit_" + secrets.token_hex(8)
    decoy = "audit_" + secrets.token_hex(8)

    def password_hash(password):
        return hashlib.sha256((password + pepper).encode("utf-8")).hexdigest()

    try:
        with open("/home/user/auth.log", "w") as f:
            f.write(
                '[2026-01-02 09:00:00] 192.0.2.1 POST /login?next=/dashboard 200 "user=relativeuser"\n'
                '[2026-01-02 09:01:00] 192.0.2.2 POST /login?next=http://malicious.example/collect 200 "user=mallory"\n'
                '[2026-01-02 09:02:00] 192.0.2.3 POST /login?next=https://evil.example/path 200 "user=trent"\n'
                '[2026-01-02 09:03:00] 192.0.2.4 POST /login?next=http://malicious.example/failed 401 "user=faileduser"\n'
            )

        with open("/home/user/users.txt", "w") as f:
            f.write(f"mallory:{password_hash(mallory_password)}\n")
            f.write(f"trent:{password_hash(trent_password)}\n")
            f.write(f"relativeuser:{password_hash(relative_password)}\n")
            f.write(f"faileduser:{password_hash(failed_password)}\n")

        with open("/home/user/wordlist.txt", "w") as f:
            f.write("\n".join([
                decoy,
                failed_password,
                trent_password,
                relative_password,
                mallory_password,
            ]) + "\n")

        if os.path.exists("/home/user/cracked.json"):
            os.remove("/home/user/cracked.json")

        env = os.environ.copy()
        env["HOME"] = "/home/user"
        env.setdefault("CARGO_HOME", "/home/user/.cargo")
        result = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", "/home/user/cracker/Cargo.toml"],
            cwd="/home/user/cracker",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, (
            "The Rust cracker failed when executed.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
        assert os.path.isfile("/home/user/cracked.json"), "The executed Rust cracker did not create /home/user/cracked.json."

        with open("/home/user/cracked.json", "r") as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f"The Rust cracker generated invalid JSON: {exc}")

        expected = {
            "mallory": mallory_password,
            "trent": trent_password,
        }
        assert actual == expected, (
            "The Rust cracker did not derive the compromised credentials from the supplied "
            f"logs, hashes, and wordlist. Expected {expected}, but got {actual}."
        )
    finally:
        for path, contents in backups.items():
            if contents is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(contents)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
