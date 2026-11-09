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
import hashlib
import io
import json
import os
import socket
import stat
import tarfile
from pathlib import Path, PurePosixPath

import pytest
import requests

MESSY = Path("/home/user/messy_project")
CLEAN = Path("/home/user/clean_project")
ARCHIVE = Path("/home/user/clean_backup.tar")
CONFIG = Path("/home/user/project_rules.json")


def digest_bytes(data):
    return len(data), hashlib.sha256(data).hexdigest()


def expected_large_digest():
    h = hashlib.sha256()
    for _ in range(10):
        h.update(b"\0" * (1024 * 1024))
    h.update(b"MAGIC_HEADER")
    return 10 * 1024 * 1024 + len(b"MAGIC_HEADER"), h.hexdigest()


EXPECTED_SOURCES = {
    "file1.log": digest_bytes(b"MAGIC_HEADER12345\n"),
    "file2.txt": digest_bytes(b"MAGIC_HEADER\n"),
    "file3.dat": digest_bytes(b"1234567890\n"),
    "large_file.bin": expected_large_digest(),
}


def file_digest(path):
    h = hashlib.sha256()
    size = 0
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            h.update(chunk)
    return size, h.hexdigest()


def contains_signature(path, signature):
    overlap = b""
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                return signature in overlap
            data = overlap + chunk
            if signature in data:
                return True
            overlap = data[-max(0, len(signature) - 1):]


def normalized_tar_name(name):
    while name.startswith("./"):
        name = name[2:]
    p = PurePosixPath(name)
    assert name and not p.is_absolute() and ".." not in p.parts, f"Unsafe tar member: {name!r}"
    return str(p)


def tcp_request(payload):
    try:
        with socket.create_connection(("127.0.0.1", 9090), timeout=5) as s:
            s.sendall(payload)
            data = b""
            while True:
                chunk = s.recv(1024)
                if not chunk:
                    break
                data += chunk
            return data.decode("utf-8")
    except (socket.error, socket.timeout) as e:
        pytest.fail(f"Failed to connect or communicate with TCP service on port 9090: {e}")


def test_services_and_artifacts():
    # Ensure the generated inputs used to derive the expected result were not replaced.
    assert CONFIG.is_file(), "Missing project_rules.json"
    with open(CONFIG, "r", encoding="utf-8") as f:
        rules = json.load(f)
    assert rules == {
        "allowed_extensions": [".log", ".dat", ".bin"],
        "magic_bytes": "4d414749435f484541444552",
    }, "project_rules.json was modified"

    assert MESSY.is_dir(), "Missing messy_project directory"
    assert set(os.listdir(MESSY)) == set(EXPECTED_SOURCES), "Source files were added, removed, or renamed"
    for name, expected_digest in EXPECTED_SOURCES.items():
        source = MESSY / name
        assert stat.S_ISREG(os.lstat(source).st_mode), f"Source is not a regular file: {name}"
        assert file_digest(source) == expected_digest, f"Source file was modified: {name}"

    allowed = set(rules["allowed_extensions"])
    signature = bytes.fromhex(rules["magic_bytes"])
    expected_names = {
        p.name for p in MESSY.iterdir()
        if p.is_file() and p.suffix in allowed and contains_signature(p, signature)
    }
    assert expected_names == {"file1.log", "large_file.bin"}

    # Verify the requested clean directory itself, including exact file contents.
    assert CLEAN.is_dir(), "Missing /home/user/clean_project"
    assert set(os.listdir(CLEAN)) == expected_names, "clean_project has missing or extra entries"
    for name in expected_names:
        cleaned = CLEAN / name
        assert stat.S_ISREG(os.lstat(cleaned).st_mode), f"Clean entry is not a regular file: {name}"
        assert file_digest(cleaned) == file_digest(MESSY / name), f"Clean file differs from source: {name}"

    assert ARCHIVE.exists(), "Missing /home/user/clean_backup.tar"
    assert stat.S_ISREG(os.lstat(ARCHIVE).st_mode), "clean_backup.tar is not a regular file"
    archive_bytes = ARCHIVE.read_bytes()

    # Require an uncompressed tar and verify every archived file's content.
    try:
        with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:") as tar:
            members = tar.getmembers()
            regular = [m for m in members if m.isfile()]
            assert all(m.isdir() or m.isfile() for m in members), "Tar contains links or special entries"
            names = [normalized_tar_name(m.name) for m in regular]
            assert len(names) == len(set(names)), "Tar contains duplicate file entries"
            assert set(names) == expected_names, f"Tar file contains incorrect files: {names}"
            assert all("/" not in name for name in names), "Tar files are not at the archive root"
            for member, name in zip(regular, names):
                extracted = tar.extractfile(member)
                assert extracted is not None
                data = extracted.read()
                assert digest_bytes(data) == file_digest(MESSY / name), f"Archived content differs for {name}"
    except tarfile.TarError as e:
        pytest.fail(f"Downloaded content is not a valid uncompressed tar file: {e}")

    # Test HTTP service and retain the original basename assertion.
    try:
        response = requests.get("http://127.0.0.1:8080/backup.tar", timeout=5)
        response.raise_for_status()
    except requests.RequestException as e:
        pytest.fail(f"Failed to fetch /backup.tar from HTTP service: {e}")

    tar_content = response.content
    assert tar_content == archive_bytes, "HTTP service did not serve /home/user/clean_backup.tar exactly"
    try:
        with tarfile.open(fileobj=io.BytesIO(tar_content), mode="r:*") as tar:
            members = tar.getnames()
            basenames = [os.path.basename(m) for m in members if not tar.getmember(m).isdir() and os.path.basename(m)]
            assert set(basenames) == {"file1.log", "large_file.bin"}, f"Tar file contains incorrect files: {basenames}"
    except tarfile.TarError as e:
        pytest.fail(f"Downloaded content is not a valid tar file: {e}")

    expected_hash = hashlib.sha256(tar_content).hexdigest()

    # Exact transcript, plus case/whitespace/punctuation normalization.
    response_text = tcp_request(b"delta protocol override\n")
    assert response_text.strip() == expected_hash, f"TCP service returned {response_text.strip()} instead of expected hash {expected_hash}"
    assert response_text == expected_hash + "\n", "Successful TCP response must be the exact hash followed by one newline"

    for payload in (
        b"  DELTA PROTOCOL OVERRIDE  \n",
        b"...Delta, protocol override!!!\n",
    ):
        assert tcp_request(payload) == expected_hash + "\n", f"Valid normalized transcript was rejected: {payload!r}"

    # Retain the original wrong-string assertion and also reject a near miss.
    response_text = tcp_request(b"random guess\n")
    assert response_text == "DENIED\n", f"TCP service returned {response_text!r} instead of 'DENIED\\n'"
    assert tcp_request(b"delta protocol overridden\n") == "DENIED\n"
TEST_EOF

set +e
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
