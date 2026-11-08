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
import os
import json
import struct
import hashlib
import requests
import pytest
import subprocess
import shutil
import signal


def parse_archive(archive_path):
    files = {}
    with open(archive_path, "rb") as f:
        magic = f.read(4)
        assert magic == b"DCAR", "Invalid archive magic"
        while True:
            file_id_bytes = f.read(2)
            if not file_id_bytes:
                break
            assert len(file_id_bytes) == 2, "Truncated file ID"
            file_id = struct.unpack(">H", file_id_bytes)[0]
            size_bytes = f.read(4)
            assert len(size_bytes) == 4, "Truncated file size"
            file_size = struct.unpack(">I", size_bytes)[0]
            path_padded = f.read(128)
            assert len(path_padded) == 128, "Truncated file path"
            path = path_padded.rstrip(b'\x00').decode('ascii')
            data = f.read(file_size)
            assert len(data) == file_size, "Truncated file data"
            files[str(file_id)] = {"path": path, "data": data}
    return files


def get_legacy_info(file_path):
    result = subprocess.run(["/app/doc_indexer", file_path], capture_output=True, text=True)
    out = result.stdout.strip()
    return out.split(":", 1)


@pytest.fixture(scope="module")
def truth_data():
    archive_path = "/home/user/legacy_docs.dcar"
    assert os.path.exists(archive_path), "Archive missing"
    return parse_archive(archive_path)


def test_extracted_files(truth_data):
    base_dir = "/home/user/extracted_docs"
    for file_id, info in truth_data.items():
        expected_path = os.path.join(base_dir, info["path"])
        assert os.path.exists(expected_path), f"Extracted file missing: {expected_path}"
        with open(expected_path, "rb") as f:
            content = f.read()
        assert content == info["data"], f"Content mismatch for {expected_path}"


def test_manifest_json(truth_data):
    manifest_path = "/home/user/manifest.json"
    assert os.path.exists(manifest_path), f"Manifest file missing: {manifest_path}"
    with open(manifest_path, "r") as f:
        manifest = json.load(f)

    base_dir = "/home/user/extracted_docs"
    for file_id, info in truth_data.items():
        assert file_id in manifest, f"File ID {file_id} missing from manifest"
        entry = manifest[file_id]
        assert entry["path"] == info["path"], f"Path mismatch for File ID {file_id}"

        expected_md5 = hashlib.md5(info["data"]).hexdigest()
        assert entry["md5"] == expected_md5, f"MD5 mismatch for File ID {file_id}"

        extracted_path = os.path.join(base_dir, info["path"])
        legacy_hash, doc_type = get_legacy_info(extracted_path)
        assert entry["legacy_hash"] == legacy_hash, f"Legacy hash mismatch for File ID {file_id}"
        assert entry["doc_type"] == doc_type, f"Doc type mismatch for File ID {file_id}"


def find_python_extraction_scripts():
    candidates = []
    skipped_dirs = {
        "/proc", "/sys", "/dev", "/tests", "/logs", "/usr/lib",
        "/usr/share", "/usr/include", "/usr/local/lib", "/var/lib",
        "/var/cache", "/var/log"
    }
    for root, dirs, files in os.walk("/", topdown=True):
        dirs[:] = [
            d for d in dirs
            if os.path.join(root, d) not in skipped_dirs
            and d not in {"__pycache__", ".git", "node_modules"}
        ]
        if root.startswith(("/proc/", "/sys/", "/dev/", "/tests/", "/logs/")):
            dirs[:] = []
            continue
        for name in files:
            path = os.path.join(root, name)
            if path == "/tmp/test_final_state.py" or path.startswith("/home/user/extracted_docs/"):
                continue
            try:
                if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "rb") as f:
                    source = f.read()
            except OSError:
                continue
            is_python = name.endswith(".py") or source.startswith(b"#!/usr/bin/env python") or source.startswith(b"#!/usr/bin/python")
            if is_python and b"DCAR" in source:
                candidates.append(path)
    return sorted(set(candidates))


def run_candidate(command, timeout=5):
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=os.path.dirname(command[1]) or "/",
        start_new_session=True,
    )
    try:
        process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()


def extracted_matches(base_dir, expected):
    for _, info in expected.items():
        path = os.path.join(base_dir, info["path"])
        if not os.path.isfile(path):
            return False
        with open(path, "rb") as f:
            if f.read() != info["data"]:
                return False
    return True


def test_python_extraction_script_exists_and_parses_archive():
    candidates = find_python_extraction_scripts()
    assert candidates, "No Python DCAR extraction script was written"

    archive = "/home/user/legacy_docs.dcar"
    base_dir = "/home/user/extracted_docs"
    manifest = "/home/user/manifest.json"
    archive_backup = archive + ".verifier-backup"
    base_backup = base_dir + ".verifier-backup"
    manifest_backup = manifest + ".verifier-backup"

    for path in (archive_backup, base_backup, manifest_backup):
        if os.path.isdir(path):
            shutil.rmtree(path)
        elif os.path.exists(path):
            os.remove(path)

    synthetic = {
        "41001": {"path": "probe/deep/random.bin", "data": os.urandom(37) + b"\x00\xffDCAR"},
        "41002": {"path": "probe/readme.txt", "data": b"verifier-generated-" + os.urandom(29)},
    }

    os.replace(archive, archive_backup)
    os.replace(base_dir, base_backup)
    if os.path.exists(manifest):
        os.replace(manifest, manifest_backup)

    succeeded = False
    try:
        with open(archive, "wb") as f:
            f.write(b"DCAR")
            for file_id, info in synthetic.items():
                path_bytes = info["path"].encode("ascii")
                f.write(struct.pack(">H", int(file_id)))
                f.write(struct.pack(">I", len(info["data"])))
                f.write(path_bytes + b"\x00" * (128 - len(path_bytes)))
                f.write(info["data"])

        argument_sets = [
            [],
            [archive],
            [archive, base_dir],
        ]
        for candidate in candidates:
            for arguments in argument_sets:
                if os.path.isdir(base_dir):
                    shutil.rmtree(base_dir)
                os.makedirs(base_dir)
                try:
                    run_candidate(["python3", candidate] + arguments)
                except (OSError, ValueError):
                    continue
                if extracted_matches(base_dir, synthetic):
                    succeeded = True
                    break
            if succeeded:
                break
    finally:
        if os.path.isdir(base_dir):
            shutil.rmtree(base_dir)
        elif os.path.exists(base_dir):
            os.remove(base_dir)
        if os.path.exists(archive):
            os.remove(archive)
        if os.path.exists(manifest):
            os.remove(manifest)
        os.replace(archive_backup, archive)
        os.replace(base_backup, base_dir)
        if os.path.exists(manifest_backup):
            os.replace(manifest_backup, manifest)

    assert succeeded, "No submitted Python script could parse and extract a verifier-generated DCAR archive"


def test_http_server_auth():
    url = "http://127.0.0.1:8080/manifest"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP server is not reachable at {url}: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized without auth, got {response.status_code}"


@pytest.mark.parametrize("path", ["/manifest", "/doc/1", "/doc/9999"])
@pytest.mark.parametrize("authorization", [None, "", "Bearer wrong-token", "bearer secret-doc-token", "secret-doc-token"])
def test_all_endpoints_reject_missing_or_invalid_credentials(path, authorization):
    headers = {} if authorization is None else {"Authorization": authorization}
    response = requests.get(f"http://127.0.0.1:8080{path}", headers=headers, timeout=2)
    assert response.status_code == 401, f"Expected 401 for {path} with invalid credentials, got {response.status_code}"


def test_http_server_manifest(truth_data):
    url = "http://127.0.0.1:8080/manifest"
    headers = {"Authorization": "Bearer secret-doc-token"}
    response = requests.get(url, headers=headers, timeout=2)

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected application/json Content-Type"

    manifest = response.json()
    for file_id in truth_data:
        assert file_id in manifest, f"File ID {file_id} missing from served manifest"

    with open("/home/user/manifest.json", "r") as f:
        expected_manifest = json.load(f)
    assert manifest == expected_manifest, "GET /manifest did not return the contents of /home/user/manifest.json"


def test_http_server_docs(truth_data):
    headers = {"Authorization": "Bearer secret-doc-token"}
    for file_id, info in truth_data.items():
        url = f"http://127.0.0.1:8080/doc/{file_id}"
        response = requests.get(url, headers=headers, timeout=2)

        assert response.status_code == 200, f"Expected 200 OK for {url}, got {response.status_code}"
        assert "application/octet-stream" in response.headers.get("Content-Type", ""), "Expected application/octet-stream Content-Type"
        assert response.content == info["data"], f"Served content mismatch for File ID {file_id}"


def test_http_server_doc_not_found():
    headers = {"Authorization": "Bearer secret-doc-token"}
    url = "http://127.0.0.1:8080/doc/9999"
    response = requests.get(url, headers=headers, timeout=2)
    assert response.status_code == 404, f"Expected 404 Not Found for non-existent file, got {response.status_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
