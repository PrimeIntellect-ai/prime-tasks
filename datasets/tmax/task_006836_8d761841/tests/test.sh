#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
import tempfile


def run_handler(script_path, filename, source):
    return subprocess.run(
        [script_path, filename, source],
        capture_output=True,
        text=True
    )


def test_phase1_upload_handler_patched():
    script_path = "/home/user/upload_handler.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing"

    # Preserve the original path traversal assertion.
    result = run_handler(script_path, "../../etc/passwd", "dummy.txt")
    assert result.returncode == 1, f"Expected script to exit with 1, got {result.returncode}"
    assert "Invalid filename" in result.stdout, "Expected 'Invalid filename' in stdout"

    # Independently exercise both required rejection rules using unpredictable names.
    marker = secrets.token_hex(10)
    malicious_names = [
        f"/{marker}",                 # slash, but no '..'
        f"prefix/{marker}",           # embedded slash, but no '..'
        f"prefix..{marker}",          # '..', but no slash
        f"..{marker}",                # leading '..', but no slash
    ]

    with tempfile.NamedTemporaryFile(delete=False) as source:
        source.write(b"upload verifier payload\n")
        source_path = source.name

    cleanup_paths = {
        os.path.join("/home/user/uploads", name.lstrip("/"))
        for name in malicious_names
        if "/" in name
    }

    safe_name = f"safe_{marker}.txt"
    safe_path = os.path.join("/home/user/uploads", safe_name)

    try:
        for filename in malicious_names:
            result = run_handler(script_path, filename, source_path)
            assert result.returncode == 1, (
                f"Expected rejection status 1 for {filename!r}, got {result.returncode}"
            )
            assert "Invalid filename" in result.stdout, (
                f"Expected 'Invalid filename' for {filename!r}"
            )

        # The original legitimate upload behavior must remain functional.
        result = run_handler(script_path, safe_name, source_path)
        assert result.returncode == 0, (
            f"Expected a safe filename to succeed, got {result.returncode}: {result.stderr}"
        )
        assert os.path.isfile(safe_path), "Safe upload was not copied to the uploads directory"
        with open(safe_path, "rb") as uploaded, open(source_path, "rb") as original:
            assert uploaded.read() == original.read(), "Safe upload content was not copied correctly"
    finally:
        os.unlink(source_path)
        if os.path.exists(safe_path):
            os.unlink(safe_path)
        for path in cleanup_paths:
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)


def test_phase1_audit_log():
    log_path = "/home/user/audit.log"
    assert os.path.isfile(log_path), f"Audit log {log_path} is missing"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "CWE-22 detected and patched", f"Audit log content incorrect: {content}"


def read_hash_manifest(path):
    manifest = {}
    line_pattern = re.compile(r"^([0-9a-fA-F]{64}) [ *](.+)$")

    with open(path, "r") as manifest_file:
        for line_number, raw_line in enumerate(manifest_file, 1):
            line = raw_line.rstrip("\n")
            if not line:
                continue
            match = line_pattern.fullmatch(line)
            assert match, f"Malformed hashes.txt entry on line {line_number}: {line!r}"
            digest, filename = match.groups()
            assert filename not in manifest, f"Duplicate hashes.txt entry for {filename!r}"
            manifest[filename] = digest.lower()

    assert manifest, "hashes.txt contains no known-good entries"
    return manifest


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def test_phase2_file_integrity():
    uploads_dir = "/home/user/uploads"
    quarantine_dir = "/home/user/quarantine"
    hashes_path = "/home/user/hashes.txt"

    assert os.path.isdir(uploads_dir), f"Directory {uploads_dir} is missing"
    assert os.path.isdir(quarantine_dir), f"Directory {quarantine_dir} is missing"
    assert os.path.isfile(hashes_path), f"Hash manifest {hashes_path} is missing"

    uploads_files = set(os.listdir(uploads_dir))
    quarantine_files = set(os.listdir(quarantine_dir))

    # Preserve the original final-state assertions.
    expected_uploads = {"file1.txt", "file2.txt"}
    expected_quarantine = {"file3.txt", "bad_actor.sh"}

    assert uploads_files == expected_uploads, f"Uploads directory should only contain {expected_uploads}, found {uploads_files}"
    assert expected_quarantine.issubset(quarantine_files), f"Quarantine directory is missing some expected files. Found {quarantine_files}"

    # Recompute integrity from the supplied manifest instead of trusting names alone.
    manifest = read_hash_manifest(hashes_path)

    for filename in uploads_files:
        path = os.path.join(uploads_dir, filename)
        assert os.path.isfile(path) and not os.path.islink(path), (
            f"Uploads entry {filename!r} is not a regular file"
        )
        assert filename in manifest, f"Unauthorized file {filename!r} remains in uploads"
        actual_digest = sha256_file(path)
        assert actual_digest == manifest[filename], (
            f"Hash mismatch for uploads/{filename}: expected {manifest[filename]}, got {actual_digest}"
        )

    for filename in quarantine_files:
        path = os.path.join(quarantine_dir, filename)
        if not os.path.isfile(path) or os.path.islink(path):
            continue
        actual_digest = sha256_file(path)
        is_known_good = filename in manifest and actual_digest == manifest[filename]
        assert not is_known_good, (
            f"Known-good file {filename!r} was incorrectly placed in quarantine"
        )


def test_phase3_tokens():
    secret_path = "/home/user/new_tokens_secret.txt"
    hashes_path = "/home/user/valid_tokens.txt"

    assert os.path.isfile(secret_path), f"File {secret_path} is missing"
    assert os.path.isfile(hashes_path), f"File {hashes_path} is missing"

    with open(secret_path, "r") as f:
        secrets_list = [line.strip() for line in f if line.strip()]

    with open(hashes_path, "r") as f:
        hashes = [line.strip() for line in f if line.strip()]

    assert len(secrets_list) == 5, f"Expected exactly 5 tokens in {secret_path}, found {len(secrets_list)}"
    assert len(hashes) == 5, f"Expected exactly 5 hashes in {hashes_path}, found {len(hashes)}"

    token_pattern = re.compile(r"^[a-zA-Z0-9]{32}$")

    for i in range(5):
        secret = secrets_list[i]
        assert token_pattern.match(secret), f"Token '{secret}' is not a 32-character alphanumeric string"

        expected_hash = hashlib.sha256(secret.encode("utf-8")).hexdigest()
        actual_hash_line = hashes[i]
        actual_hash = actual_hash_line.split()[0]

        assert expected_hash == actual_hash, f"Hash mismatch at line {i+1}. Expected {expected_hash}, found {actual_hash}"


def test_phase4_network_rules():
    rules_path = "/home/user/network_rules.conf"
    assert os.path.isfile(rules_path), f"File {rules_path} is missing"

    with open(rules_path, "r") as f:
        content = f.read()

    assert "DENY 198.51.100.42" in content, f"Expected rule 'DENY 198.51.100.42' not found in {rules_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
