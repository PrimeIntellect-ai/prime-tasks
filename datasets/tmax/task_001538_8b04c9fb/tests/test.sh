#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import time
import zipfile

SCRIPT_PATH = "/home/user/process_docs.sh"
DROP_DIR = "/home/user/docs_drop"
EXTRACTED_DIR = "/home/user/docs_extracted"
MANIFEST_PATH = "/home/user/docs_manifest.txt"
LOCK_PATH = "/tmp/docs_process.lock"
EXPECTED_FILES = {}


def prepare_random_archive():
    global EXPECTED_FILES

    token = secrets.token_hex(24)
    EXPECTED_FILES = {
        "readme.md": f"# Documentation {token}\n".encode(),
        "guides/user_guide.md": f"Guide contents {token}\n".encode(),
        "notes.txt": f"Non-Markdown file {token}\n".encode(),
        "asset.bin": secrets.token_bytes(700),
        "api/v1/endpoints.md": f"# Endpoints {token}\n".encode(),
        "api/v1/auth.md": f"Authentication {token}\n".encode(),
        "api/v1/advanced.md": f"Advanced API {token}\n".encode(),
    }

    shutil.rmtree(DROP_DIR, ignore_errors=True)
    shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)
    if os.path.lexists(MANIFEST_PATH):
        os.unlink(MANIFEST_PATH)
    if os.path.lexists(LOCK_PATH):
        os.unlink(LOCK_PATH)
    os.makedirs(DROP_DIR, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        deep_zip = os.path.join(tmp, "deeper.zip")
        with zipfile.ZipFile(deep_zip, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("advanced.md", EXPECTED_FILES["api/v1/advanced.md"])

        outer_zip = os.path.join(tmp, "nested_api.zip")
        with zipfile.ZipFile(outer_zip, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("api/v1/endpoints.md", EXPECTED_FILES["api/v1/endpoints.md"])
            zf.writestr("api/v1/auth.md", EXPECTED_FILES["api/v1/auth.md"])
            zf.write(deep_zip, "api/v1/deeper.zip")

        tar_path = os.path.join(tmp, "main_docs.tar.gz")
        source = os.path.join(tmp, "source")
        os.makedirs(os.path.join(source, "guides"))
        for rel_path in ("readme.md", "guides/user_guide.md", "notes.txt", "asset.bin"):
            path = os.path.join(source, rel_path)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(EXPECTED_FILES[rel_path])
        shutil.copyfile(outer_zip, os.path.join(source, "nested_api.zip"))

        with tarfile.open(tar_path, "w:gz") as tf:
            for name in ("readme.md", "guides", "notes.txt", "asset.bin", "nested_api.zip"):
                tf.add(os.path.join(source, name), arcname=name)

        with open(tar_path, "rb") as f:
            archive = f.read()
        assert len(archive) > 200
        for index, offset in enumerate(range(0, len(archive), 97)):
            suffix = chr(ord("a") + index // 26) + chr(ord("a") + index % 26)
            part = os.path.join(DROP_DIR, "docs_archive.tar.gz.part" + suffix)
            with open(part, "wb") as f:
                f.write(archive[offset:offset + 97])


def test_script_exists_and_executable():
    """Check if the script exists, is executable, and contains flock."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "flock" in content, "Script does not appear to use 'flock' for concurrency control."


def test_script_execution_and_manifest():
    """Exercise locking, extraction, recursive zip handling, and the manifest."""
    prepare_random_archive()

    lock_fd = os.open(LOCK_PATH, os.O_CREAT | os.O_RDWR, 0o666)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    contender = subprocess.Popen(
        [SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    try:
        time.sleep(1.0)
        assert not os.path.exists(EXTRACTED_DIR), (
            "The script modified the extraction output while another process held "
            "/tmp/docs_process.lock."
        )
        assert not os.path.exists(MANIFEST_PATH), (
            "The script generated the manifest while another process held "
            "/tmp/docs_process.lock."
        )
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)

    if contender.poll() is None:
        stdout, stderr = contender.communicate(timeout=20)
        assert contender.returncode == 0, (
            f"Script execution failed with return code {contender.returncode}.\n"
            f"Stdout: {stdout}\nStderr: {stderr}"
        )
    else:
        # A nonblocking flock implementation may legitimately skip a contended run.
        result = subprocess.run(
            [SCRIPT_PATH], capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, (
            f"Script execution failed with return code {result.returncode}.\n"
            f"Stderr: {result.stderr}"
        )

    assert os.path.isdir(EXTRACTED_DIR), (
        f"Extraction directory {EXTRACTED_DIR} was not created."
    )
    assert os.path.isfile(MANIFEST_PATH), (
        f"Manifest file {MANIFEST_PATH} was not created."
    )

    actual_files = {}
    for root, _, files in os.walk(EXTRACTED_DIR):
        for filename in files:
            path = os.path.join(root, filename)
            rel_path = os.path.relpath(path, EXTRACTED_DIR).replace(os.sep, "/")
            with open(path, "rb") as f:
                actual_files[rel_path] = f.read()

    assert actual_files == EXPECTED_FILES, (
        "Extracted files do not match the randomized multipart archive, including "
        "the recursively nested zip contents."
    )

    md_paths = sorted(path for path in EXPECTED_FILES if path.endswith(".md"))
    expected_lines = [
        f"{hashlib.sha256(EXPECTED_FILES[path]).hexdigest()}  {path}"
        for path in md_paths
    ]
    expected_manifest = "\n".join(expected_lines)

    with open(MANIFEST_PATH, "r") as f:
        actual_manifest = f.read().strip()

    assert actual_manifest == expected_manifest, (
        "The manifest contents do not match the expected SHA256 checksums, "
        "relative paths, sorting, and formatting."
    )


def test_no_zip_files_left():
    """Ensure that all nested .zip files were removed after extraction."""
    assert os.path.isdir(EXTRACTED_DIR), (
        f"Extraction directory {EXTRACTED_DIR} was not created."
    )

    zip_files = []
    for root, _, files in os.walk(EXTRACTED_DIR):
        for filename in files:
            if filename.endswith(".zip"):
                zip_files.append(os.path.join(root, filename))

    assert len(zip_files) == 0, (
        f"Nested zip files were not removed after extraction: {zip_files}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
