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
import re
import subprocess
import tarfile
import tempfile
import requests
import pytest

BASE_URL = "http://127.0.0.1:9090"
BINARY_PATH = "/app/vendored/fast-tar/fast-tar"


def get_file_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(8192):
            sha256.update(chunk)
    return sha256.hexdigest()


def directory_files(root):
    files = {}
    for dirpath, _, filenames in os.walk(root):
        for filename in filenames:
            full_path = os.path.join(dirpath, filename)
            relative_path = os.path.relpath(full_path, root).replace(os.sep, "/")
            with open(full_path, "rb") as f:
                files[relative_path] = f.read()
    return files


def assert_archive_matches(archive_path, expected_files):
    try:
        with tarfile.open(archive_path, mode="r:*") as archive:
            actual_files = {}
            for member in archive.getmembers():
                name = member.name.replace("\\", "/")
                assert not name.startswith("/"), f"Archive contains absolute path {name}"
                assert ".." not in name.split("/"), f"Archive contains unsafe path {name}"
                if member.isdir():
                    continue
                assert member.isfile(), f"Archive contains unsupported entry {name}"
                assert name not in actual_files, f"Archive contains duplicate entry {name}"
                extracted = archive.extractfile(member)
                assert extracted is not None, f"Could not read archive entry {name}"
                actual_files[name] = extracted.read()
    except (tarfile.TarError, OSError) as e:
        pytest.fail(f"{archive_path} is not a valid tar archive: {e}")

    assert set(actual_files) == set(expected_files), (
        f"Archive members differ: expected {sorted(expected_files)}, "
        f"got {sorted(actual_files)}"
    )
    for path, expected_content in expected_files.items():
        assert actual_files[path] == expected_content, f"Content mismatch for {path} in archive"


def test_fast_tar_built():
    binary_path = BINARY_PATH
    assert os.path.isfile(binary_path), f"The fast-tar binary was not built at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"The fast-tar binary at {binary_path} is not executable"

    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast-tar is not a Linux ELF executable"

    result = subprocess.run(
        ["go", "version", "-m", binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Could not inspect fast-tar Go build metadata: {result.stdout}"
    assert re.search(r":\s+go\d", result.stdout), "fast-tar is not a Go-built executable"


def test_fast_tar_creates_valid_archive():
    with tempfile.TemporaryDirectory(prefix="fast_tar_verify_") as temp_dir:
        input_dir = os.path.join(temp_dir, "input")
        os.makedirs(os.path.join(input_dir, "nested", "deeper"))
        files = {
            "root.json": os.urandom(73),
            "nested/data.csv": b"key,value\n" + os.urandom(117),
            "nested/deeper/users.xml": b"<users>" + os.urandom(41) + b"</users>",
        }
        for relative_path, content in files.items():
            full_path = os.path.join(input_dir, *relative_path.split("/"))
            with open(full_path, "wb") as f:
                f.write(content)

        output_path = os.path.join(temp_dir, "generated.ftar")
        result = subprocess.run(
            [BINARY_PATH, "-out", output_path, input_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"fast-tar failed to create an archive: stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert os.path.isfile(output_path), "fast-tar did not create the requested output file"
        assert_archive_matches(output_path, files)


def test_index_json_on_disk():
    index_path = "/home/user/index.json"
    assert os.path.isfile(index_path), f"{index_path} does not exist"

    with open(index_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{index_path} is not valid JSON")

    assert "files" in data, "JSON missing 'files' key"

    expected_files = {
        "sales/Q1.csv": get_file_sha256("/home/user/raw_data/sales/Q1.csv"),
        "users.xml": get_file_sha256("/home/user/raw_data/users.xml")
    }

    actual_files = {item.get("path"): item.get("hash") for item in data["files"]}

    for path, expected_hash in expected_files.items():
        assert path in actual_files, f"File {path} missing from index.json"
        assert actual_files[path] == expected_hash, f"Hash mismatch for {path} in index.json"


def test_backup_ftar_on_disk():
    backup_path = "/home/user/backup.ftar"
    assert os.path.isfile(backup_path), f"{backup_path} does not exist"
    assert os.path.getsize(backup_path) > 0, f"{backup_path} is empty"
    expected_files = directory_files("/home/user/raw_data")
    assert expected_files, "Raw data directory unexpectedly contains no files"
    assert_archive_matches(backup_path, expected_files)


def test_server_ping():
    try:
        response = requests.get(f"{BASE_URL}/ping", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/ping: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert response.text.strip() == "pong", f"Expected body 'pong', got '{response.text}'"


def test_server_index():
    try:
        response = requests.get(f"{BASE_URL}/index", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/index: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /index is not valid JSON")

    assert "files" in data, "JSON response missing 'files' key"

    expected_files = {
        "sales/Q1.csv": get_file_sha256("/home/user/raw_data/sales/Q1.csv"),
        "users.xml": get_file_sha256("/home/user/raw_data/users.xml")
    }

    actual_files = {item.get("path"): item.get("hash") for item in data["files"]}

    for path, expected_hash in expected_files.items():
        assert path in actual_files, f"File {path} missing from /index response"
        assert actual_files[path] == expected_hash, f"Hash mismatch for {path} in /index response"


def test_server_download():
    try:
        response = requests.get(f"{BASE_URL}/download", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/download: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/octet-stream" in content_type, f"Expected Content-Type application/octet-stream, got '{content_type}'"

    assert len(response.content) > 0, "Response body from /download is empty"

    # Compare with the local file
    backup_path = "/home/user/backup.ftar"
    if os.path.exists(backup_path):
        with open(backup_path, 'rb') as f:
            local_content = f.read()
        assert response.content == local_content, "Downloaded content does not match /home/user/backup.ftar"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
