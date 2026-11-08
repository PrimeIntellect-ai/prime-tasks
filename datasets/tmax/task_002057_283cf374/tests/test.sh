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
import csv
import hashlib
import io
import os
import secrets
import zipfile

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
AUTH_HEADER = {"Authorization": "Bearer crimson skyline protocol"}
ARTIFACTS_DIR = "/home/user/artifacts"
MANIFEST_PATH = os.path.join(ARTIFACTS_DIR, "manifest.csv")


def create_zip_in_memory(file_contents):
    mem_zip = io.BytesIO()
    with zipfile.ZipFile(mem_zip, "w") as zf:
        for filename, content in file_contents.items():
            if isinstance(content, str):
                content = content.encode("utf-8")
            zf.writestr(filename, content)
    return mem_zip.getvalue()


def get_sha256(content):
    if isinstance(content, str):
        content = content.encode("utf-8")
    return hashlib.sha256(content).hexdigest()


def post_archive(contents, headers=AUTH_HEADER):
    archive = create_zip_in_memory(contents)
    return requests.post(
        f"{BASE_URL}/upload",
        headers=headers,
        files={"archive": ("upload.zip", archive, "application/zip")},
        timeout=10,
    )


def assert_success(resp):
    assert resp.status_code == 200, resp.text
    try:
        body = resp.json()
    except ValueError:
        pytest.fail(f"Expected JSON success response, got: {resp.text}")
    assert body == {"status": "success"}, f"Unexpected success response: {body}"


def assert_manifest_matches_filesystem():
    assert os.path.isfile(MANIFEST_PATH), "manifest.csv was not created"
    with open(MANIFEST_PATH, "rb") as f:
        disk_manifest = f.read()

    resp = requests.get(f"{BASE_URL}/manifest", headers=AUTH_HEADER, timeout=10)
    assert resp.status_code == 200, resp.text
    assert resp.content == disk_manifest, "GET /manifest did not return the exact manifest file"

    text = disk_manifest.decode("utf-8")
    reader = csv.DictReader(io.StringIO(text))
    rows = list(reader)
    assert reader.fieldnames == ["filename", "sha256"], reader.fieldnames

    actual = {}
    for row in rows:
        assert set(row) == {"filename", "sha256"}
        assert row["filename"] not in actual, f"Duplicate manifest row: {row['filename']}"
        actual[row["filename"]] = row["sha256"]

    expected = {}
    for root, _, files in os.walk(ARTIFACTS_DIR):
        for name in files:
            path = os.path.join(root, name)
            if os.path.abspath(path) == os.path.abspath(MANIFEST_PATH):
                continue
            rel = os.path.relpath(path, ARTIFACTS_DIR).replace(os.sep, "/")
            with open(path, "rb") as f:
                expected[rel] = hashlib.sha256(f.read()).hexdigest()

    assert actual == expected, f"Manifest mismatch. Expected {expected}, got {actual}"
    return disk_manifest


def test_original_repository_sequence():
    try:
        requests.get(BASE_URL, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to server at {BASE_URL}. Is it running?")

    safe_zip_bytes = create_zip_in_memory({"test.txt": "hello"})
    resp_no_auth = requests.post(
        f"{BASE_URL}/upload",
        files={"archive": ("safe.zip", safe_zip_bytes, "application/zip")},
        timeout=10,
    )
    assert resp_no_auth.status_code == 401, (
        f"Expected 401 Unauthorized when missing auth, got {resp_no_auth.status_code}. "
        f"Response: {resp_no_auth.text}"
    )

    malicious_zip_bytes = create_zip_in_memory({"../../../home/user/hacked.txt": "hacked"})
    resp_malicious = requests.post(
        f"{BASE_URL}/upload",
        headers=AUTH_HEADER,
        files={"archive": ("malicious.zip", malicious_zip_bytes, "application/zip")},
        timeout=10,
    )
    assert resp_malicious.status_code == 400, (
        f"Expected 400 Bad Request for Zip Slip attempt, got {resp_malicious.status_code}. "
        f"Response: {resp_malicious.text}"
    )
    try:
        json_resp = resp_malicious.json()
        assert json_resp.get("error") == "Zip Slip detected", (
            f"Expected JSON error message 'Zip Slip detected', got {json_resp}"
        )
    except ValueError:
        pytest.fail(f"Expected JSON response for Zip Slip error, got: {resp_malicious.text}")

    assert not os.path.exists("/home/user/artifacts/hacked.txt"), (
        "Zip Slip failed: hacked.txt was extracted into artifacts dir."
    )
    assert not os.path.exists("/home/user/hacked.txt"), (
        "Zip Slip failed: hacked.txt was extracted outside artifacts dir."
    )

    safe_v1_bytes = create_zip_in_memory({"config.json": "v1"})
    resp_v1 = requests.post(
        f"{BASE_URL}/upload",
        headers=AUTH_HEADER,
        files={"archive": ("safe_v1.zip", safe_v1_bytes, "application/zip")},
        timeout=10,
    )
    assert resp_v1.status_code == 200, (
        f"Expected 200 OK for safe v1 upload, got {resp_v1.status_code}. Response: {resp_v1.text}"
    )
    assert resp_v1.json() == {"status": "success"}
    with open(os.path.join(ARTIFACTS_DIR, "config.json"), "rb") as f:
        assert f.read() == b"v1"

    resp_manifest_v1 = requests.get(f"{BASE_URL}/manifest", headers=AUTH_HEADER, timeout=10)
    assert resp_manifest_v1.status_code == 200, (
        f"Expected 200 OK for GET /manifest, got {resp_manifest_v1.status_code}. "
        f"Response: {resp_manifest_v1.text}"
    )
    manifest_v1_text = resp_manifest_v1.text
    reader_v1 = csv.DictReader(io.StringIO(manifest_v1_text))
    rows_v1 = list(reader_v1)
    assert reader_v1.fieldnames == ["filename", "sha256"], (
        f"Expected CSV header 'filename,sha256', got {reader_v1.fieldnames}"
    )
    v1_hash = get_sha256("v1")
    config_row_v1 = next((row for row in rows_v1 if row["filename"] == "config.json"), None)
    assert config_row_v1 is not None, "config.json missing from manifest after v1 upload"
    assert config_row_v1["sha256"] == v1_hash, (
        f"Expected hash {v1_hash} for config.json, got {config_row_v1['sha256']}"
    )

    safe_v2_bytes = create_zip_in_memory({"config.json": "v2", "data.xml": "<data/>"})
    resp_v2 = requests.post(
        f"{BASE_URL}/upload",
        headers=AUTH_HEADER,
        files={"archive": ("safe_v2.zip", safe_v2_bytes, "application/zip")},
        timeout=10,
    )
    assert resp_v2.status_code == 200, (
        f"Expected 200 OK for safe v2 upload, got {resp_v2.status_code}. Response: {resp_v2.text}"
    )
    assert resp_v2.json() == {"status": "success"}
    with open(os.path.join(ARTIFACTS_DIR, "config.json"), "rb") as f:
        assert f.read() == b"v2"
    with open(os.path.join(ARTIFACTS_DIR, "data.xml"), "rb") as f:
        assert f.read() == b"<data/>"

    resp_manifest_v2 = requests.get(f"{BASE_URL}/manifest", headers=AUTH_HEADER, timeout=10)
    assert resp_manifest_v2.status_code == 200, (
        f"Expected 200 OK for GET /manifest, got {resp_manifest_v2.status_code}. "
        f"Response: {resp_manifest_v2.text}"
    )
    manifest_v2_text = resp_manifest_v2.text
    reader_v2 = csv.DictReader(io.StringIO(manifest_v2_text))
    rows_v2 = list(reader_v2)
    v2_hash = get_sha256("v2")
    data_hash = get_sha256("<data/>")
    config_row_v2 = next((row for row in rows_v2 if row["filename"] == "config.json"), None)
    data_row_v2 = next((row for row in rows_v2 if row["filename"] == "data.xml"), None)
    assert config_row_v2 is not None, "config.json missing from manifest after v2 upload"
    assert config_row_v2["sha256"] == v2_hash, (
        f"Expected updated hash {v2_hash} for config.json, got {config_row_v2['sha256']}"
    )
    assert data_row_v2 is not None, "data.xml missing from manifest after v2 upload"
    assert data_row_v2["sha256"] == data_hash, (
        f"Expected hash {data_hash} for data.xml, got {data_row_v2['sha256']}"
    )


def test_randomized_auth_extraction_manifest_and_zip_slip():
    nonce = secrets.token_hex(12)
    denied_name = f"denied_{nonce}.bin"
    denied_path = os.path.join(ARTIFACTS_DIR, denied_name)
    wrong_headers = {"Authorization": f"Bearer wrong-{secrets.token_hex(16)}"}

    denied = post_archive({denied_name: secrets.token_bytes(37)}, headers=wrong_headers)
    assert denied.status_code == 401, denied.text
    assert not os.path.exists(denied_path), "Unauthorized upload changed the artifact directory"
    assert requests.get(f"{BASE_URL}/manifest", timeout=10).status_code == 401
    assert requests.get(
        f"{BASE_URL}/manifest", headers=wrong_headers, timeout=10
    ).status_code == 401

    name_a = f"artifact_{nonce}.bin"
    name_b = f"notes_{nonce}.txt"
    content_a = secrets.token_bytes(173)
    content_b = (f"random payload {nonce} " + secrets.token_hex(31)).encode()

    first = post_archive({name_a: content_a, name_b: content_b})
    assert_success(first)
    for name, expected in ((name_a, content_a), (name_b, content_b)):
        path = os.path.join(ARTIFACTS_DIR, name)
        assert os.path.isfile(path), f"Safe archive member {name} was not extracted"
        with open(path, "rb") as f:
            assert f.read() == expected, f"Extracted bytes differ for {name}"
    assert_manifest_matches_filesystem()

    replacement = secrets.token_bytes(211)
    name_c = f"extra_{nonce}.dat"
    content_c = secrets.token_bytes(89)
    second = post_archive({name_a: replacement, name_c: content_c})
    assert_success(second)
    with open(os.path.join(ARTIFACTS_DIR, name_a), "rb") as f:
        assert f.read() == replacement, "Overwritten artifact did not receive new contents"
    with open(os.path.join(ARTIFACTS_DIR, name_b), "rb") as f:
        assert f.read() == content_b, "Incremental upload removed an existing artifact"
    with open(os.path.join(ARTIFACTS_DIR, name_c), "rb") as f:
        assert f.read() == content_c
    manifest_before_attacks = assert_manifest_matches_filesystem()

    traversal_target = f"traversal_{nonce}.txt"
    traversal_canary = f"canary_traversal_{nonce}.txt"
    traversal_outside = os.path.join("/tmp", traversal_target)
    traversal_inside = os.path.join(ARTIFACTS_DIR, traversal_canary)
    assert not os.path.exists(traversal_outside)
    traversal = post_archive({
        traversal_canary: b"must not be partially extracted",
        f"../../../tmp/{traversal_target}": b"escaped",
    })
    assert traversal.status_code == 400, traversal.text
    assert traversal.json() == {"error": "Zip Slip detected"}
    assert not os.path.exists(traversal_outside), "Traversal member escaped to /tmp"
    assert not os.path.exists(traversal_inside), "Archive was partially extracted before rejection"
    with open(MANIFEST_PATH, "rb") as f:
        assert f.read() == manifest_before_attacks, "Rejected archive changed the manifest"

    absolute_target = f"absolute_{nonce}.txt"
    absolute_canary = f"canary_absolute_{nonce}.txt"
    absolute_outside = os.path.join("/tmp", absolute_target)
    absolute_inside = os.path.join(ARTIFACTS_DIR, absolute_canary)
    normalized_inside = os.path.join(ARTIFACTS_DIR, "tmp", absolute_target)
    assert not os.path.exists(absolute_outside)
    absolute = post_archive({
        absolute_canary: b"must not be partially extracted",
        f"/tmp/{absolute_target}": b"absolute escape",
    })
    assert absolute.status_code == 400, absolute.text
    assert absolute.json() == {"error": "Zip Slip detected"}
    assert not os.path.exists(absolute_outside), "Absolute archive member escaped to /tmp"
    assert not os.path.exists(absolute_inside), "Archive was partially extracted before rejection"
    assert not os.path.exists(normalized_inside), "Absolute path was normalized and extracted instead of rejected"
    with open(MANIFEST_PATH, "rb") as f:
        assert f.read() == manifest_before_attacks, "Rejected archive changed the manifest"

    assert_manifest_matches_filesystem()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
