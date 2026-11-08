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
import glob
import json
import os
import re
import secrets
import shutil
import subprocess
import tarfile

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
DATA_DIR = "/app/data"
PROJECT_DIR = "/app/wal-config-server"
WAL_FILE = os.path.join(DATA_DIR, "config.wal")
SNAPSHOT_FILE = os.path.join(DATA_DIR, "snapshot.json")
SYMLINK_FILE = os.path.join(DATA_DIR, "current.tar.gz")


def post(path, payload=None):
    try:
        response = requests.post(f"{BASE_URL}{path}", data=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to server for POST {path}: {exc}")
    assert response.status_code == 200, (
        f"POST {path} failed with status {response.status_code}. "
        f"Response: {response.text}"
    )


def test_server_and_state():
    # The repaired package installation target must actually succeed.
    result = subprocess.run(
        ["make", "install"], cwd=PROJECT_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90
    )
    assert result.returncode == 0, f"make install failed:\n{result.stdout}"

    os.makedirs(DATA_DIR, exist_ok=True)
    for path in glob.glob(os.path.join(DATA_DIR, "*")):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    # Seed an existing snapshot so replacement can be distinguished from an
    # in-place rewrite. A compliant temp-file + rename creates a new inode.
    with open(SNAPSHOT_FILE, "w", encoding="utf-8") as f:
        json.dump({"sentinel": True}, f)
    old_snapshot_inode = os.stat(SNAPSHOT_FILE).st_ino

    token = secrets.token_hex(10)
    dynamic_key = f"price_{token}"
    other_key = f"naïve_{token}"
    entries = [
        {"key": "app_name", "value": "tést_app"},
        {"key": "version", "value": "1.0"},
        {"key": dynamic_key, "value": f"€12.50_{token}"},
        {"key": other_key, "value": f"café_{token}"},
        {"key": "version", "value": "1.1"},
        {"key": dynamic_key, "value": f"final—“{token}”"},
    ]

    payloads = [
        json.dumps(entry, ensure_ascii=False, separators=(",", ":")).encode("cp1252")
        for entry in entries
    ]
    for payload in payloads:
        post("/append", payload)

    # /append must produce one strict UTF-8 JSON object per WAL line, rather
    # than ignoring the request body or prematurely writing the snapshot.
    assert os.path.isfile(WAL_FILE), f"WAL file {WAL_FILE} does not exist."
    raw_wal = open(WAL_FILE, "rb").read()
    assert raw_wal.endswith(b"\n"), "WAL does not end with a complete line."
    try:
        wal_text = raw_wal.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        pytest.fail(f"WAL is not strict UTF-8: {exc}")
    wal_lines = wal_text.splitlines()
    assert len(wal_lines) == len(entries), "WAL does not contain one line per append."
    try:
        wal_entries = [json.loads(line) for line in wal_lines]
    except json.JSONDecodeError as exc:
        pytest.fail(f"WAL contains an invalid JSON line: {exc}")
    assert wal_entries == entries, f"WAL entries mismatch: {wal_entries}"
    assert os.stat(SNAPSHOT_FILE).st_ino == old_snapshot_inode
    with open(SNAPSHOT_FILE, "r", encoding="utf-8") as f:
        assert json.load(f) == {"sentinel": True}, "/append modified snapshot.json"

    post("/commit")

    assert os.path.isdir(DATA_DIR), f"Directory {DATA_DIR} does not exist."
    assert os.path.isfile(WAL_FILE), f"WAL file {WAL_FILE} does not exist."
    assert os.path.getsize(WAL_FILE) == 0, f"WAL file {WAL_FILE} is not empty."

    expected_data = {}
    for entry in entries:
        expected_data[entry["key"]] = entry["value"]

    assert os.path.isfile(SNAPSHOT_FILE), f"Snapshot file {SNAPSHOT_FILE} does not exist."
    assert os.stat(SNAPSHOT_FILE).st_ino != old_snapshot_inode, (
        "snapshot.json was modified in place instead of replaced atomically"
    )
    try:
        with open(SNAPSHOT_FILE, "r", encoding="utf-8") as f:
            snapshot_data = json.load(f)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        pytest.fail(f"File {SNAPSHOT_FILE} is not valid UTF-8 JSON: {exc}")
    assert snapshot_data == expected_data, (
        f"Snapshot data mismatch. Expected {expected_data}, got {snapshot_data}."
    )
    # Retain the original fixed-case assertions as part of the randomized test.
    assert snapshot_data["app_name"] == "tést_app"
    assert snapshot_data["version"] == "1.1"

    assert os.path.islink(SYMLINK_FILE), f"{SYMLINK_FILE} is not a symbolic link."
    target = os.readlink(SYMLINK_FILE)
    target_path = target if os.path.isabs(target) else os.path.join(DATA_DIR, target)
    target_path = os.path.abspath(target_path)
    assert os.path.dirname(target_path) == DATA_DIR, "Archive was created outside /app/data."
    assert os.path.isfile(target_path), f"Symlink target {target_path} does not exist."
    assert re.fullmatch(r"snapshot_[0-9]+\.tar\.gz", os.path.basename(target_path)), (
        f"Archive name does not contain a Unix timestamp: {target_path}"
    )

    try:
        with tarfile.open(target_path, "r:gz") as tar:
            members = tar.getmembers()
            names = tar.getnames()
            assert "snapshot.json" in names, f"snapshot.json not found in {target_path}."
            assert len(names) == 1, f"Tarball contains unexpected files: {names}"
            assert names == ["snapshot.json"] and members[0].isfile(), (
                "Archive must contain exactly one regular file named snapshot.json"
            )
            archived = tar.extractfile(members[0])
            assert archived is not None, "Could not extract snapshot.json from tarball."
            tar_data = json.loads(archived.read().decode("utf-8", errors="strict"))
            assert tar_data == expected_data, (
                f"Tarball snapshot mismatch. Expected {expected_data}, got {tar_data}."
            )
    except (tarfile.TarError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        pytest.fail(f"Failed to read tarball {target_path}: {exc}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
