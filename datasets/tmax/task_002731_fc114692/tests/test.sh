#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import re
import pytest

def test_exploit_gen_exists():
    assert os.path.exists("/home/user/exploit_gen.rs"), "The Rust script /home/user/exploit_gen.rs is missing."
    assert os.path.isfile("/home/user/exploit_gen.rs"), "/home/user/exploit_gen.rs is not a regular file."

def test_report_json_exists():
    assert os.path.exists("/home/user/report.json"), "The report file /home/user/report.json is missing."
    assert os.path.isfile("/home/user/report.json"), "/home/user/report.json is not a regular file."

def test_report_json_contents():
    # Read the handler source to derive expected values dynamically
    handler_path = "/home/user/upload_handler.rs"
    assert os.path.exists(handler_path), f"Source file {handler_path} is missing."

    with open(handler_path, 'r') as f:
        content = f.read()

    salt_match = re.search(r'let salt\s*=\s*"([^"]+)";', content)
    assert salt_match is not None, "Could not extract salt from upload_handler.rs"
    salt = salt_match.group(1)

    path_match = re.search(r'let path\s*=\s*format!\("([^"]+)\{\}",\s*filename\);', content)
    assert path_match is not None, "Could not extract upload path from upload_handler.rs"
    upload_path = path_match.group(1)

    # Derive expected token
    token_input = f"admin{salt}".encode('utf-8')
    expected_token = hashlib.md5(token_input).hexdigest()

    # Derive expected path traversal payload
    path_parts = [p for p in upload_path.split('/') if p]
    expected_payload = "../" * len(path_parts) + "var/www/html/index.html"

    # Derive expected SHA256 of the token
    expected_sha256 = hashlib.sha256(expected_token.encode('utf-8')).hexdigest()

    # Expected header
    expected_header = "content-security-policy"

    # Read the student's report
    with open('/home/user/report.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/report.json does not contain valid JSON.")

    assert "admin_token" in data, "Key 'admin_token' is missing from report.json."
    assert data["admin_token"] == expected_token, f"Incorrect admin_token. Expected {expected_token}."

    assert "path_traversal_payload" in data, "Key 'path_traversal_payload' is missing from report.json."
    assert data["path_traversal_payload"] == expected_payload, f"Incorrect path_traversal_payload. Expected {expected_payload}."

    assert "missing_header" in data, "Key 'missing_header' is missing from report.json."
    assert data["missing_header"].lower() == expected_header, f"Incorrect missing_header. Expected {expected_header}."

    assert "token_sha256" in data, "Key 'token_sha256' is missing from report.json."
    assert data["token_sha256"] == expected_sha256, f"Incorrect token_sha256. Expected {expected_sha256}."
TEST_EOF

run_submission() {
    test -f /home/user/exploit_gen.rs || return 1
    rm -f /home/user/report.json

    local build_dir
    build_dir=$(mktemp -d)

    if [ -f /home/user/exploit_workspace/Cargo.toml ]; then
        mkdir -p "$build_dir/workspace"
        cp -a /home/user/exploit_workspace/. "$build_dir/workspace/"
        cp /home/user/exploit_gen.rs "$build_dir/workspace/verifier_exploit_gen.rs"
        cat << 'CARGO_EOF' >> "$build_dir/workspace/Cargo.toml"

[[bin]]
name = "verifier_exploit_gen"
path = "verifier_exploit_gen.rs"
CARGO_EOF
        if ! cargo run --quiet --manifest-path "$build_dir/workspace/Cargo.toml" --bin verifier_exploit_gen; then
            rustc /home/user/exploit_gen.rs -o "$build_dir/exploit_gen" || {
                rm -rf "$build_dir"
                return 1
            }
            "$build_dir/exploit_gen" || {
                rm -rf "$build_dir"
                return 1
            }
        fi
    else
        rustc /home/user/exploit_gen.rs -o "$build_dir/exploit_gen" || {
            rm -rf "$build_dir"
            return 1
        }
        "$build_dir/exploit_gen" || {
            rm -rf "$build_dir"
            return 1
        }
    fi

    rm -rf "$build_dir"
    test -f /home/user/report.json
}

if { run_submission && python3 -m pytest /tmp/test_final_state.py -x --tb=short; } 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
