#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import urllib.request
import urllib.error
import time

def get_elf_files(base_dir):
    elf_files = []
    for root, _, files in os.walk(base_dir):
        for file in files:
            path = os.path.join(root, file)
            try:
                with open(path, 'rb') as f:
                    magic = f.read(4)
                    if magic == b'\x7FELF':
                        elf_files.append(path)
            except Exception:
                pass
    return elf_files

def compute_sha256(path):
    sha256 = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(65536), b""):
            sha256.update(block)
    return sha256.hexdigest()

def test_manifest_exists_and_valid():
    manifest_path = '/home/user/repo/manifest.json'
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            assert False, "Manifest is not valid JSON"

    assert "artifacts" in manifest, "Manifest missing 'artifacts' key"
    assert isinstance(manifest["artifacts"], list), "'artifacts' should be a list"

def test_manifest_contents_and_chunks():
    manifest_path = '/home/user/repo/manifest.json'
    if not os.path.isfile(manifest_path):
        pytest.fail("Manifest file missing")

    with open(manifest_path, 'r') as f:
        manifest = json.load(f)

    artifacts = manifest.get("artifacts", [])

    elf_files = get_elf_files('/home/user/incoming_artifacts')
    assert len(elf_files) > 0, "No ELF files found in incoming directory"

    assert len(artifacts) == len(elf_files), f"Expected {len(elf_files)} artifacts in manifest, found {len(artifacts)}"

    manifest_by_name = {a.get("original_name"): a for a in artifacts}

    for elf_path in elf_files:
        original_name = os.path.basename(elf_path)
        assert original_name in manifest_by_name, f"Artifact {original_name} missing from manifest"

        artifact = manifest_by_name[original_name]
        expected_sha256 = compute_sha256(elf_path)
        assert artifact.get("original_sha256") == expected_sha256, f"Incorrect SHA256 for {original_name}"

        file_size = os.path.getsize(elf_path)
        expected_chunks = (file_size + 524288 - 1) // 524288

        chunks = artifact.get("chunks", [])
        assert len(chunks) == expected_chunks, f"Expected {expected_chunks} chunks for {original_name}, found {len(chunks)}"

        with open(elf_path, 'rb') as f:
            for i, chunk_info in enumerate(chunks):
                expected_chunk_name = f"{expected_sha256}_chunk_{i:04d}"
                assert chunk_info.get("chunk_name") == expected_chunk_name, f"Incorrect chunk name: {chunk_info.get('chunk_name')}"

                chunk_data = f.read(524288)
                expected_chunk_sha256 = hashlib.sha256(chunk_data).hexdigest()
                assert chunk_info.get("chunk_sha256") == expected_chunk_sha256, f"Incorrect chunk SHA256 for {expected_chunk_name}"

                chunk_file_path = os.path.join('/home/user/repo/chunks', expected_chunk_name)
                assert os.path.isfile(chunk_file_path), f"Chunk file missing at {chunk_file_path}"

                actual_chunk_sha256 = compute_sha256(chunk_file_path)
                assert actual_chunk_sha256 == expected_chunk_sha256, f"Chunk file {expected_chunk_name} has incorrect data"

def test_server_running():
    pid_file = '/home/user/repo/server.pid'
    assert os.path.isfile(pid_file), f"PID file missing at {pid_file}"

    with open(pid_file, 'r') as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), "PID file does not contain a valid integer"
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running"

def test_http_server_serving():
    url = "http://127.0.0.1:8080/manifest.json"
    max_retries = 3
    for i in range(max_retries):
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=2) as response:
                assert response.status == 200, f"Expected HTTP 200, got {response.status}"
                data = response.read()
                manifest = json.loads(data.decode('utf-8'))
                assert "artifacts" in manifest, "Served manifest missing 'artifacts'"
            return
        except urllib.error.URLError as e:
            if i == max_retries - 1:
                assert False, f"Failed to connect to HTTP server at {url}: {e}"
            time.sleep(1)
        except json.JSONDecodeError:
            assert False, "Served manifest is not valid JSON"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
