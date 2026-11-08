#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import subprocess
import uuid

BACKUP_PATH = "/home/user/backup/nginx.conf.bak"
NGINX_PATH = "/home/user/nginx_setup/nginx.conf"
PROJECT_DIR = "/app/log-sanitizer"
INSTALLED_BINARY = "/home/user/bin/log-sanitizer"
BUILT_BINARY = "/app/log-sanitizer/target/release/log-sanitizer"
ORIGINAL_NGINX = b'''server {
    listen 80;
    location / {
        proxy_pass http://127.0.0.1:9999;
    }
}
'''
SIGNATURES = ["../", "UNION SELECT", "<script>"]


def run_sanitizer(path, input_text):
    result = subprocess.run(
        [path],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}: {result.stderr}"
    )
    return result.stdout


def expected_output(input_text):
    return "".join(
        line for line in input_text.splitlines(keepends=True)
        if not any(signature in line for signature in SIGNATURES)
    )


def test_nginx_backup_exists_and_is_original():
    assert os.path.isfile(BACKUP_PATH), f"Backup file {BACKUP_PATH} does not exist"
    with open(BACKUP_PATH, "rb") as f:
        assert f.read() == ORIGINAL_NGINX, "Nginx backup does not contain the original configuration"


def test_nginx_config_fixed():
    assert os.path.isfile(NGINX_PATH), f"Missing Nginx config at {NGINX_PATH}"
    with open(NGINX_PATH, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8080;" in content, \
        "Nginx config does not contain the fixed proxy_pass directive (8080)"
    assert "9999" not in content, "Nginx config still contains the old port 9999"


def test_rust_project_builds_and_binary_is_installed_copy():
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Cargo.toml")), "Missing Cargo.toml"
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src/main.rs")), "Missing src/main.rs"

    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust release build failed:\n{result.stdout}\n{result.stderr}"

    assert os.path.isfile(INSTALLED_BINARY), f"Compiled binary {INSTALLED_BINARY} does not exist"
    assert os.access(INSTALLED_BINARY, os.X_OK), f"Compiled binary {INSTALLED_BINARY} is not executable"
    assert os.path.isfile(BUILT_BINARY), f"Release build did not produce {BUILT_BINARY}"
    assert os.access(BUILT_BINARY, os.X_OK), f"Built binary {BUILT_BINARY} is not executable"

    with open(BUILT_BINARY, "rb") as f:
        built_bytes = f.read()
    with open(INSTALLED_BINARY, "rb") as f:
        installed_bytes = f.read()
    assert built_bytes.startswith(b"\x7fELF"), "Cargo release artifact is not a native executable"
    assert installed_bytes == built_bytes, \
        "Installed log-sanitizer is not a copy of the current Cargo release artifact"


def test_shipped_corpora_filtering():
    clean_files = glob.glob("/app/corpora/clean/*")
    evil_files = glob.glob("/app/corpora/evil/*")
    assert clean_files, "No clean corpus files found"
    assert evil_files, "No evil corpus files found"

    clean_modified = []
    evil_bypassed = []

    for clean_file in clean_files:
        with open(clean_file, "r") as f:
            original = f.read()
        output = run_sanitizer(INSTALLED_BINARY, original)
        if output != original:
            clean_modified.append(os.path.basename(clean_file))

    for evil_file in evil_files:
        with open(evil_file, "r") as f:
            original = f.read()
        output = run_sanitizer(INSTALLED_BINARY, original)
        expected = expected_output(original)
        if output != expected:
            evil_bypassed.append(os.path.basename(evil_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil corpora filtered incorrectly: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean corpora modified: {', '.join(clean_modified)}")
    assert not errors, " | ".join(errors)


def test_unseen_mixed_inputs_are_filtered_exactly():
    nonce = uuid.uuid4().hex
    clean_lines = [
        f"{nonce} clean GET /index-{uuid.uuid4().hex} HTTP/1.1 200\n",
        f"{nonce} ordinary POST /api/{uuid.uuid4().hex} HTTP/1.1 201\n",
        f"{nonce} text with UNION but no SQL phrase {uuid.uuid4().hex}\n",
        f"{nonce} literal script tag without angle brackets {uuid.uuid4().hex}\n",
    ]
    malicious_lines = [
        f"{nonce} GET /private/../secret-{uuid.uuid4().hex} HTTP/1.1\n",
        f"{nonce} query={uuid.uuid4().hex} UNION SELECT password FROM accounts\n",
        f"{nonce} comment=<script>alert('{uuid.uuid4().hex}')</script>\n",
        f"prefix-../-{uuid.uuid4().hex}-suffix\n",
    ]

    mixed = clean_lines + malicious_lines
    random.SystemRandom().shuffle(mixed)
    input_text = "".join(mixed)
    expected = expected_output(input_text)

    assert run_sanitizer(INSTALLED_BINARY, input_text) == expected
    assert run_sanitizer(BUILT_BINARY, input_text) == expected

    clean_only = "".join(reversed(clean_lines))
    assert run_sanitizer(INSTALLED_BINARY, clean_only) == clean_only
    assert run_sanitizer(INSTALLED_BINARY, "".join(malicious_lines)) == ""
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
