#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import re
import subprocess
import tarfile
import time
import urllib.error
import urllib.request

import pytest

BACKUP_DIR = "/home/user/backups"
SERVICE_URL = "http://localhost:8080/upload"


def upload_archive(index, file_a_content, file_b_content, hacked_content=None,
                   absolute_name=None, absolute_content=None):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for name, content in (("A", file_a_content), ("B", file_b_content)):
            info = tarfile.TarInfo(name=name)
            info.size = len(content)
            tar.addfile(info, io.BytesIO(content))

        if hacked_content is not None:
            info = tarfile.TarInfo(name="../../../home/user/hacked.txt")
            info.size = len(hacked_content)
            tar.addfile(info, io.BytesIO(hacked_content))

        if absolute_name is not None:
            info = tarfile.TarInfo(name=absolute_name)
            info.size = len(absolute_content)
            tar.addfile(info, io.BytesIO(absolute_content))

    file_data = buf.getvalue()
    boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
    body = (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"file\"; filename=\"backup_{index}.tar.gz\"\r\n"
        f"Content-Type: application/gzip\r\n\r\n"
    ).encode() + file_data + f"\r\n--{boundary}--\r\n".encode()

    req = urllib.request.Request(SERVICE_URL, data=body)
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    req.add_header("Content-Length", str(len(body)))
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
    except urllib.error.URLError as exc:
        pytest.fail(
            f"Failed to upload archive {index} to {SERVICE_URL}. Error: {exc}. "
            "Is Nginx and the Flask app running and accepting large files?"
        )


def redis_contains_digest(digest):
    try:
        import redis
        tokens = (digest.hexdigest().encode(), digest.digest())
        for db in range(16):
            client = redis.Redis(host="127.0.0.1", port=6379, db=db,
                                 socket_connect_timeout=2, socket_timeout=2)
            for key in client.scan_iter():
                blobs = [key]
                kind = client.type(key)
                if kind == b"string":
                    blobs.append(client.get(key) or b"")
                elif kind == b"hash":
                    for field, value in client.hgetall(key).items():
                        blobs.extend((field, value))
                elif kind == b"set":
                    blobs.extend(client.smembers(key))
                elif kind == b"zset":
                    blobs.extend(client.zrange(key, 0, -1))
                elif kind == b"list":
                    blobs.extend(client.lrange(key, 0, -1))
                elif kind == b"stream":
                    for entry_id, fields in client.xrange(key):
                        blobs.append(entry_id)
                        for field, value in fields.items():
                            blobs.extend((field, value))
                if any(token in blob for token in tokens for blob in blobs if isinstance(blob, bytes)):
                    return True
        return False
    except Exception as exc:
        pytest.fail(f"Could not inspect Redis deduplication state: {exc}")


def test_backup_system():
    with open("/app/nginx/nginx.conf", "r", encoding="utf-8") as config_file:
        config = re.sub(r"#.*", "", config_file.read())
    assert re.search(r"\bclient_max_body_size\s+500m\s*;", config, re.IGNORECASE), \
        "Nginx client_max_body_size is not configured to 500MB"

    os.makedirs(BACKUP_DIR, exist_ok=True)
    before_dirs = {
        name for name in os.listdir(BACKUP_DIR)
        if os.path.isdir(os.path.join(BACKUP_DIR, name))
    }

    file_a_content = os.urandom(10 * 1024 * 1024)
    file_b_content = os.urandom(10 * 1024 * 1024)
    hacked_content = b"hacked_content_test"
    absolute_content = os.urandom(37)
    absolute_path = f"/tmp/backup_verifier_escape_{os.urandom(12).hex()}"
    assert not os.path.exists(absolute_path)

    for i in range(5):
        upload_archive(
            i,
            file_a_content,
            file_b_content,
            hacked_content if i == 0 else None,
            absolute_path if i == 0 else None,
            absolute_content if i == 0 else None,
        )

    time.sleep(0.5)

    # Preserve the original path-traversal assertion and also check the absolute path.
    assert not os.path.exists("/home/user/hacked.txt"), \
        "Security Vulnerability: Path traversal allowed writing to /home/user/hacked.txt"
    assert not os.path.exists(absolute_path), \
        f"Security Vulnerability: absolute tar path wrote to {absolute_path}"

    after_dirs = {
        name for name in os.listdir(BACKUP_DIR)
        if os.path.isdir(os.path.join(BACKUP_DIR, name))
    }
    new_dirs = sorted(after_dirs - before_dirs)
    assert len(new_dirs) == 5, \
        f"Expected one newly extracted backup directory per upload, found {len(new_dirs)}"

    a_paths = []
    b_paths = []
    contained_hacked = []
    contained_absolute = []
    backup_root = os.path.realpath(BACKUP_DIR)

    for name in new_dirs:
        target = os.path.join(BACKUP_DIR, name)
        a_path = os.path.join(target, "A")
        b_path = os.path.join(target, "B")
        assert os.path.isfile(a_path) and not os.path.islink(a_path), f"Missing extracted file {a_path}"
        assert os.path.isfile(b_path) and not os.path.islink(b_path), f"Missing extracted file {b_path}"
        with open(a_path, "rb") as stream:
            assert stream.read() == file_a_content, f"Extracted contents differ for {a_path}"
        with open(b_path, "rb") as stream:
            assert stream.read() == file_b_content, f"Extracted contents differ for {b_path}"
        a_paths.append(a_path)
        b_paths.append(b_path)

        target_real = os.path.realpath(target)
        assert os.path.commonpath((backup_root, target_real)) == backup_root
        for root, dirs, files in os.walk(target, followlinks=False):
            for filename in files:
                path = os.path.join(root, filename)
                assert not os.path.islink(path), f"Archive created an unsafe symlink: {path}"
                real_path = os.path.realpath(path)
                assert os.path.commonpath((target_real, real_path)) == target_real, \
                    f"Extracted file escaped its backup directory: {path}"
                with open(path, "rb") as stream:
                    content = stream.read()
                if content == hacked_content:
                    contained_hacked.append(path)
                if content == absolute_content:
                    contained_absolute.append(path)

    assert len(contained_hacked) == 1, \
        "The traversal member was not normalized and extracted exactly once inside its backup directory"
    assert len(contained_absolute) == 1, \
        "The absolute-path member was not normalized and extracted exactly once inside its backup directory"

    # Verify actual hard-link deduplication of the uploaded data, independent of preexisting files.
    a_inodes = {(os.stat(path).st_dev, os.stat(path).st_ino) for path in a_paths}
    b_inodes = {(os.stat(path).st_dev, os.stat(path).st_ino) for path in b_paths}
    assert len(a_inodes) == 1, "Identical A files from separate uploads are not hard-linked"
    assert len(b_inodes) == 1, "Identical B files from separate uploads are not hard-linked"
    assert a_inodes != b_inodes, "Different file contents were incorrectly deduplicated together"
    assert all(os.stat(path).st_nlink >= 5 for path in a_paths + b_paths), \
        "Deduplicated files do not have the expected hard-link count"

    # The required SHA-256 mappings must be represented in Redis.
    assert redis_contains_digest(hashlib.sha256(file_a_content)), \
        "Redis does not contain a SHA-256 mapping for uploaded file A"
    assert redis_contains_digest(hashlib.sha256(file_b_content)), \
        "Redis does not contain a SHA-256 mapping for uploaded file B"

    # Preserve the original deduplication-ratio assertion.
    def get_size(logical=False):
        cmd = ["du", "-sb"]
        if logical:
            cmd.append("-l")
        cmd.append(BACKUP_DIR)
        try:
            return float(subprocess.check_output(cmd).decode().split()[0])
        except Exception as exc:
            pytest.fail(f"Failed to calculate directory size: {exc}")

    physical_size = get_size(logical=False)
    logical_size = get_size(logical=True)
    ratio = logical_size / physical_size if physical_size > 0 else 0
    assert ratio >= 3.0, \
        f"Deduplication ratio metric failed. Expected >= 3.0, got {ratio:.2f} " \
        f"(Logical: {logical_size}, Physical: {physical_size})"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
