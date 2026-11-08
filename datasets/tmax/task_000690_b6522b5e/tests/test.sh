#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import requests
import pytest

def compute_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_server_and_manifest():
    experiment_id = "ALPHA-992"
    base_url = f"http://127.0.0.1:8000/{experiment_id}"
    manifest_url = f"{base_url}/manifest.json"

    try:
        response = requests.get(manifest_url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or fetch manifest.json: {e}")

    assert response.status_code == 200, f"Expected status code 200 for manifest.json, got {response.status_code}"

    try:
        manifest = response.json()
    except ValueError:
        pytest.fail(f"manifest.json does not contain valid JSON. Response text: {response.text}")

    expected_files = {
        "meta_a.json": "/app/raw_data/folder1/meta_a.json",
        "records.csv": "/app/raw_data/folder2/subfolder/records.csv",
        "config.xml": "/app/raw_data/folder2/config.xml"
    }

    assert len(manifest) == len(expected_files), f"Expected {len(expected_files)} entries in manifest, got {len(manifest)}"

    for filename, original_path in expected_files.items():
        assert filename in manifest, f"Expected file {filename} missing from manifest.json"

        expected_sha = compute_sha256(original_path)
        assert manifest[filename].lower() == expected_sha, f"SHA-256 mismatch for {filename} in manifest.json"

        file_url = f"{base_url}/{filename}"
        try:
            file_response = requests.get(file_url, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to fetch {filename} from server: {e}")

        assert file_response.status_code == 200, f"Expected status code 200 for {filename}, got {file_response.status_code}"

        downloaded_sha = hashlib.sha256(file_response.content).hexdigest()
        assert downloaded_sha == expected_sha, f"SHA-256 mismatch for downloaded file {filename}"

def test_local_files_organized():
    experiment_id = "ALPHA-992"
    target_dir = f"/home/user/organized_dataset/{experiment_id}"

    assert os.path.isdir(target_dir), f"Target directory {target_dir} does not exist"

    expected_files = ["meta_a.json", "records.csv", "config.xml", "manifest.json"]
    for filename in expected_files:
        filepath = os.path.join(target_dir, filename)
        assert os.path.isfile(filepath), f"Expected file {filepath} not found in target directory"
        assert not os.path.islink(filepath), f"Expected {filepath} to be a copied file, not a symbolic link"

    expected_sources = {
        "meta_a.json": "/app/raw_data/folder1/meta_a.json",
        "records.csv": "/app/raw_data/folder2/subfolder/records.csv",
        "config.xml": "/app/raw_data/folder2/config.xml"
    }
    expected_manifest = {}
    for filename, original_path in expected_sources.items():
        expected_sha = compute_sha256(original_path)
        expected_manifest[filename] = expected_sha
        local_path = os.path.join(target_dir, filename)
        assert compute_sha256(local_path) == expected_sha, f"Local file {local_path} does not match the source file"

    manifest_path = os.path.join(target_dir, "manifest.json")
    try:
        with open(manifest_path, "r", encoding="utf-8") as f:
            local_manifest = json.load(f)
    except (OSError, UnicodeDecodeError, ValueError) as e:
        pytest.fail(f"Local manifest.json is not a readable valid JSON file: {e}")

    assert isinstance(local_manifest, dict), "Local manifest.json must contain a single JSON object"
    assert local_manifest == expected_manifest, "Local manifest.json does not contain the exact expected filenames and lowercase SHA-256 checksums"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
