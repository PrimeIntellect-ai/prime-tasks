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
import json
import os
import tarfile
import time

import pytest
import requests

STAGING = "/home/user/archive_staging"
CLOUD = "/home/user/cloud_data"
TARBALL = "/home/user/cold_storage.tar.gz"
EXPECTED_COLD = {
    **{f"project_a/old_{i}.dat": 682 for i in range(1, 16)},
    "project_a/old_16.dat": 10,
}
EXPECTED_NEW = {f"project_b/new_{i}.dat": 250 for i in range(1, 21)}


def regular_file_manifest(root):
    assert os.path.isdir(root), f"Directory {root} does not exist."
    result = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for name in filenames:
            path = os.path.join(dirpath, name)
            assert not os.path.islink(path), f"Unexpected symlink: {path}"
            assert os.path.isfile(path), f"Unexpected non-regular file: {path}"
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            result[rel] = os.path.getsize(path)
    return result


def normalized_tar_name(name):
    assert not name.startswith("/"), f"Archive contains an absolute path: {name}"
    parts = [part for part in name.split("/") if part not in ("", ".")]
    assert ".." not in parts, f"Archive contains path traversal: {name}"
    if parts and parts[0] == "archive_staging":
        parts = parts[1:]
    return "/".join(parts)


def validated_archive_manifest():
    assert os.path.exists(TARBALL), f"Tarball {TARBALL} does not exist."
    assert tarfile.is_tarfile(TARBALL), f"File {TARBALL} is not a valid tar archive."
    with open(TARBALL, "rb") as f:
        assert f.read(2) == b"\x1f\x8b", "cold_storage.tar.gz is not gzip-compressed."

    manifest = {}
    with tarfile.open(TARBALL, "r:gz") as archive:
        for member in archive.getmembers():
            name = normalized_tar_name(member.name)
            if member.isdir():
                assert name in ("", "project_a"), f"Unexpected directory in archive: {member.name}"
                continue
            assert member.isfile(), f"Unexpected non-regular archive member: {member.name}"
            assert name, f"Archive contains a file with an empty path: {member.name}"
            assert name not in manifest, f"Duplicate archive member: {name}"
            extracted = archive.extractfile(member)
            assert extracted is not None
            data = extracted.read()
            staged_path = os.path.join(STAGING, *name.split("/"))
            assert os.path.isfile(staged_path), f"Archive member has no staged file: {name}"
            with open(staged_path, "rb") as staged:
                assert data == staged.read(), f"Archive content differs from staged file: {name}"
            manifest[name] = len(data)
    return manifest


def archived_totals():
    manifest = regular_file_manifest(STAGING)
    assert manifest == EXPECTED_COLD, f"Incorrect staged cold-file manifest: {manifest}"

    cutoff = time.time() - 45 * 24 * 60 * 60
    for rel in manifest:
        path = os.path.join(STAGING, *rel.split("/"))
        assert os.path.getmtime(path) < cutoff, f"Staged file is not older than 45 days: {rel}"

    archive_manifest = validated_archive_manifest()
    assert archive_manifest == manifest, (
        f"Archive manifest does not match staging. Archive: {archive_manifest}; staging: {manifest}"
    )
    return len(archive_manifest), sum(archive_manifest.values())


def test_fstab_addition():
    fstab_path = "/home/user/fstab_addition"
    assert os.path.exists(fstab_path), f"File {fstab_path} does not exist."
    with open(fstab_path, "r") as f:
        content = f.read().strip()
    expected = "cold-vault.internal:/data /mnt/archive nfs defaults,ro 0 0"
    assert content == expected, f"fstab_addition content is incorrect. Got: {content}"


def test_cold_storage_tarball_and_staging():
    count, total = archived_totals()
    assert count == 16, f"Expected 16 archived files, got {count}"
    assert total == 10240, f"Expected 10240 archived bytes, got {total}"


def test_cloud_data_after_move():
    manifest = regular_file_manifest(CLOUD)
    assert manifest == EXPECTED_NEW, f"cloud_data does not contain exactly the expected warm files: {manifest}"
    cutoff = time.time() - 45 * 24 * 60 * 60
    for rel in manifest:
        path = os.path.join(CLOUD, *rel.split("/"))
        assert os.path.getmtime(path) >= cutoff, f"Cold file remains in cloud_data: {rel}"


def test_http_server_valid_auth():
    expected_count, expected_bytes = archived_totals()
    url = "http://127.0.0.1:8080/report"
    headers = {"Authorization": "Bearer FinOpsSecure2024"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    assert data.get("archived_files_count") == 16, f"Expected 16 archived files, got {data.get('archived_files_count')}"
    assert data.get("archived_bytes") == 10240, f"Expected 10240 archived bytes, got {data.get('archived_bytes')}"
    assert data.get("status") == "optimized", f"Expected status 'optimized', got {data.get('status')}"
    assert data == {
        "archived_files_count": expected_count,
        "archived_bytes": expected_bytes,
        "status": "optimized",
    }, f"Report does not match the validated archive: {data}"


def test_http_server_invalid_auth():
    url = "http://127.0.0.1:8080/report"
    headers = {"Authorization": "Bearer WrongToken"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server: {e}")
    assert response.status_code == 401, f"Expected status code 401 for invalid token, got {response.status_code}"


def test_http_server_missing_auth():
    url = "http://127.0.0.1:8080/report"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server: {e}")
    assert response.status_code == 401, f"Expected status code 401 for missing token, got {response.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
