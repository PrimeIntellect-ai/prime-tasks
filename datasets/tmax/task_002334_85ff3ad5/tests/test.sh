#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import json
import io
import secrets
import subprocess
import sys
import tarfile


def test_incoming_directory_empty():
    """Test that the incoming directory is empty (files were processed and deleted)."""
    incoming_dir = "/home/user/incoming"
    assert os.path.exists(incoming_dir), f"Directory {incoming_dir} should exist."
    files = os.listdir(incoming_dir)
    assert len(files) == 0, f"Incoming directory is not empty. Found: {files}"


def test_app_conf_deployed():
    """Test that app.conf was successfully deployed with the correct content."""
    app_conf_path = "/home/user/configs/app.conf"
    assert os.path.exists(app_conf_path), f"File {app_conf_path} was not deployed."

    with open(app_conf_path, "r") as f:
        content = f.read()

    expected_content = "port=8080\nenable_feature=true\n"
    assert content == expected_content, f"Content of {app_conf_path} is incorrect."


def test_zip_slip_prevented():
    """Test that the malicious file was not extracted/deployed."""
    hacked_txt_path = "/home/user/configs/hacked.txt"
    assert not os.path.exists(hacked_txt_path), f"Malicious file {hacked_txt_path} was deployed! Zip Slip prevention failed."


def test_security_log():
    """Test that the security log correctly recorded the rejected file."""
    log_path = "/home/user/configs/security.log"
    assert os.path.exists(log_path), f"Security log {log_path} does not exist."

    with open(log_path, "r") as f:
        log_content = f.read()

    expected_log_entry = "REJECTED: bundle2.tar.gz - ../../../home/user/configs/hacked.txt"
    assert expected_log_entry in log_content, f"Security log does not contain the expected rejection entry. Found: {log_content}"


def test_manifest_generated():
    """Test that the manifest.txt was generated correctly with the right SHA-256 hash."""
    manifest_path = "/home/user/configs/manifest.txt"
    assert os.path.exists(manifest_path), f"Manifest file {manifest_path} does not exist."

    expected_content = b"port=8080\nenable_feature=true\n"
    expected_hash = hashlib.sha256(expected_content).hexdigest()
    expected_line = f"{expected_hash}  app.conf"

    with open(manifest_path, "r") as f:
        manifest_content = f.read()

    assert expected_line in manifest_content, f"Manifest does not contain the expected entry for app.conf. Found: {manifest_content}"


def test_script_processes_new_random_archive_securely():
    """Execute the submitted script against a fresh archive with unpredictable data."""
    script_path = "/home/user/config_watcher.py"
    assert os.path.isfile(script_path), f"Required Python script {script_path} does not exist or is not a regular file."

    token = secrets.token_hex(10)
    archive_name = f"dynamic_{token}.tar.gz"
    archive_path = os.path.join("/home/user/incoming", archive_name)
    extraction_name = f"dynamic_{token}"
    extraction_dir = os.path.join("/home/user/extracted", extraction_name)
    deployed_name = f"generated_{token}.conf"
    nested_member = f"nested/{deployed_name}"
    malicious_member = f"../../configs/escaped_{token}.txt"
    escaped_path = f"/home/user/configs/escaped_{token}.txt"
    payload = f"token={token}\nvalue={secrets.token_hex(16)}\n".encode()
    malicious_payload = b"must not escape extraction\n"
    deploy_document = json.dumps({"deploy": [nested_member]}).encode()

    def add_bytes(tar, name, data):
        info = tarfile.TarInfo(name=name)
        info.size = len(data)
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(data))

    with tarfile.open(archive_path, "w:gz") as tar:
        add_bytes(tar, "deploy.json", deploy_document)
        add_bytes(tar, nested_member, payload)
        add_bytes(tar, malicious_member, malicious_payload)

    result = subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"config_watcher.py exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    assert not os.path.exists(archive_path), "The newly processed archive was not deleted."
    assert os.path.isfile(os.path.join(extraction_dir, "deploy.json")), "deploy.json was not extracted into the required archive-specific directory."
    extracted_payload = os.path.join(extraction_dir, nested_member)
    assert os.path.isfile(extracted_payload), "The safe nested archive member was not extracted."
    with open(extracted_payload, "rb") as f:
        assert f.read() == payload, "The extracted file content is incorrect."

    deployed_path = os.path.join("/home/user/configs", deployed_name)
    assert os.path.isfile(deployed_path), "The listed configuration file was not deployed with a flattened filename."
    with open(deployed_path, "rb") as f:
        assert f.read() == payload, "The dynamically deployed configuration content is incorrect."

    assert not os.path.exists(escaped_path), "A traversal member escaped into the configs directory."

    security_log = "/home/user/configs/security.log"
    assert os.path.isfile(security_log), "security.log is missing after rejecting a traversal member."
    expected_rejection = f"REJECTED: {archive_name} - {malicious_member}"
    with open(security_log, "r") as f:
        log_content = f.read()
    assert expected_rejection in log_content, f"Missing dynamic rejection entry: {expected_rejection!r}"

    expected_manifest_line = f"{hashlib.sha256(payload).hexdigest()}  {deployed_name}"
    with open("/home/user/configs/manifest.txt", "r") as f:
        manifest_content = f.read()
    assert expected_manifest_line in manifest_content, f"Missing dynamic manifest entry: {expected_manifest_line!r}"

    remaining = os.listdir("/home/user/incoming")
    assert remaining == [], f"Incoming directory is not empty after execution: {remaining}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
