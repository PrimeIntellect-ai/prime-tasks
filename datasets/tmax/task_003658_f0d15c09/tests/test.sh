#!/bin/bash
set +e
mkdir -p /logs/verifier
passed=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import pytest

CLEAN_DIR = "/home/user/backups/clean"
MANIFEST_PATH = "/home/user/backups/manifest.json"

EXPECTED_MANIFEST = {
    "recovered_plain.dat": "a251b6819ebf4e1792fc240bd06927d60da11504936d8021307b22591eef350f",
    "recovered_db_dump.txt": "a6fc14daae245d6101ec2926be2a40e1136b6cbdbd5ce4020a67e2315bba98e4",
    "recovered_secret.conf": "43924f793da86c47fc7b8f21915c2cf92bb098a5e1281cb9f257a6e1d2c6c0ca"
}

def compute_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_clean_directory_contents():
    assert os.path.isdir(CLEAN_DIR), f"Directory {CLEAN_DIR} does not exist."

    files = set(os.listdir(CLEAN_DIR))
    expected_files = set(EXPECTED_MANIFEST.keys())

    missing = expected_files - files
    extra = files - expected_files

    assert not missing, f"Missing files in {CLEAN_DIR}: {missing}"
    assert not extra, f"Extra unexpected files in {CLEAN_DIR}: {extra}"

def test_manifest_exists_and_valid():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."

    try:
        with open(MANIFEST_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")

    assert isinstance(data, dict), "Manifest JSON should be a dictionary."

def test_manifest_content():
    with open(MANIFEST_PATH, "r") as f:
        data = json.load(f)

    assert data == EXPECTED_MANIFEST, f"Manifest contents do not match expected values.\nExpected: {EXPECTED_MANIFEST}\nGot: {data}"

def test_file_checksums():
    with open(MANIFEST_PATH, "r") as f:
        data = json.load(f)

    for filename, expected_hash in data.items():
        filepath = os.path.join(CLEAN_DIR, filename)
        assert os.path.isfile(filepath), f"File {filepath} listed in manifest does not exist."

        actual_hash = compute_sha256(filepath)
        assert actual_hash == expected_hash, f"Checksum mismatch for {filename}. Expected {expected_hash}, got {actual_hash}."
TEST_EOF

if [ ! -f /home/user/cleanup.py ] || [ -L /home/user/cleanup.py ]; then
    echo "cleanup.py is missing or is not a regular script" >&2
    passed=0
elif ! python3 -m py_compile /home/user/cleanup.py; then
    echo "cleanup.py is not valid Python" >&2
    passed=0
fi

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=0
fi

cat << 'DYNAMIC_EOF' > /tmp/test_cleanup_behavior.py
import gzip
import hashlib
import io
import json
import os
import secrets
import shutil
import subprocess
import zipfile

RAW = "/home/user/backups/raw"
CLEAN = "/home/user/backups/clean"
MANIFEST = "/home/user/backups/manifest.json"
SCRIPT = "/home/user/cleanup.py"

def sha256(data):
    return hashlib.sha256(data).hexdigest()

def gzip_member(data, original_name):
    output = io.BytesIO()
    with gzip.GzipFile(filename=original_name, mode="wb", fileobj=output, mtime=0) as archive:
        archive.write(data)
    return output.getvalue()

def zip_member(member_name, data):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(member_name, data)
    return output.getvalue()

token = secrets.token_hex(8)
plain_name = f"ordinary_{token}.zip"
gzip_payload_name = f"database_{token}.txt"
nested_payload_name = f"secret_{token}.conf"
plain_data = b"plain dynamic data\x00" + secrets.token_bytes(41)
gzip_data = b"dynamic database row\n" + secrets.token_bytes(37)
nested_data = b"dynamic nested secret\n" + secrets.token_bytes(43)

shutil.rmtree(RAW, ignore_errors=True)
shutil.rmtree(CLEAN, ignore_errors=True)
os.makedirs(RAW)
os.makedirs(CLEAN)
try:
    os.unlink(MANIFEST)
except FileNotFoundError:
    pass

with open(os.path.join(RAW, plain_name), "wb") as f:
    f.write(plain_data)

with open(os.path.join(RAW, f"compressed_{token}.tmp"), "wb") as f:
    f.write(gzip_member(gzip_data, gzip_payload_name))

inner_gzip_name = f"inner_{token}.dat"
outer_data = zip_member(inner_gzip_name, gzip_member(nested_data, nested_payload_name))
with open(os.path.join(RAW, f"mystery_{token}.bak"), "wb") as f:
    f.write(outer_data)

loop_a = f"loop_a_{token}.link"
loop_b = f"loop_b_{token}.link"
os.symlink(loop_b, os.path.join(RAW, loop_a))
os.symlink(loop_a, os.path.join(RAW, loop_b))

expected = {
    "recovered_" + plain_name: sha256(plain_data),
    "recovered_" + gzip_payload_name: sha256(gzip_data),
    "recovered_" + nested_payload_name: sha256(nested_data),
}

result = subprocess.run(
    ["python3", SCRIPT],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=20,
)
assert result.returncode == 0, f"cleanup.py failed:\nstdout={result.stdout}\nstderr={result.stderr}"
assert os.path.isdir(CLEAN), "cleanup.py did not create the clean directory"
assert set(os.listdir(CLEAN)) == set(expected), f"Unexpected clean directory contents: {os.listdir(CLEAN)}"
assert os.path.isfile(MANIFEST), "cleanup.py did not create the manifest"
with open(MANIFEST, "r") as f:
    manifest = json.load(f)
assert isinstance(manifest, dict), "Manifest is not a dictionary"
assert manifest == expected, f"Dynamic manifest mismatch. Expected {expected}, got {manifest}"
for filename, expected_hash in expected.items():
    path = os.path.join(CLEAN, filename)
    assert os.path.isfile(path) and not os.path.islink(path), f"Invalid recovered file: {filename}"
    with open(path, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()
    assert actual_hash == expected_hash, f"Checksum mismatch for {filename}"
DYNAMIC_EOF

if [ "$passed" -eq 1 ]; then
    if ! timeout 30s python3 /tmp/test_cleanup_behavior.py 2>&1; then
        passed=0
    fi
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
