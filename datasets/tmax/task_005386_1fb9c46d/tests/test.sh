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
import csv
import hashlib
import stat
import subprocess
import requests

INCOMING_DIR = "/app/data/incoming"
ARCHIVE_DIR = "/app/data/archive"
ORIGINAL_INPUTS = {
    "file1.json": b'{"id": 1, "email": "admin@secret.com", "notes": "CONFIDENTIAL"}\n',
    "file2.csv": b'2,bob@secret.com,CONFIDENTIAL data here\n',
    "file3.json": b'{"id": 3, "email": "public@open.com", "notes": "Public info"}\n',
}


def get_file_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def build_expected_archive():
    expected = {}
    for root, _, files in os.walk(INCOMING_DIR):
        for name in files:
            if not (name.endswith(".json") or name.endswith(".csv")):
                continue
            source_path = os.path.join(root, name)
            with open(source_path, "r", encoding="utf-8", newline="") as f:
                contents = f.read()
            if "CONFIDENTIAL" not in contents:
                continue
            assert name not in expected, f"Multiple matching incoming files have the same base filename: {name}"
            if name.endswith(".json"):
                data = json.loads(contents)
                if isinstance(data, dict) and "email" in data:
                    data["email"] = "[REDACTED]"
                expected[name] = ("json", data)
            else:
                rows = list(csv.reader(contents.splitlines()))
                transformed = []
                for row in rows:
                    row = list(row)
                    if len(row) > 1 and "@" in row[1]:
                        row[1] = "[REDACTED]"
                    transformed.append(row)
                expected[name] = ("csv", transformed)
    return expected


def test_incoming_inputs_are_intact():
    for name, expected_bytes in ORIGINAL_INPUTS.items():
        path = os.path.join(INCOMING_DIR, name)
        assert os.path.isfile(path), f"Required incoming file {name} is missing."
        with open(path, "rb") as f:
            assert f.read() == expected_bytes, f"Incoming file {name} was modified."


def test_archive_files_exist_and_redacted():
    assert os.path.isdir(ARCHIVE_DIR), f"Archive directory {ARCHIVE_DIR} does not exist."
    expected = build_expected_archive()
    assert set(os.listdir(ARCHIVE_DIR)) == set(expected), "Archive does not contain exactly the required files."

    for name, (kind, expected_data) in expected.items():
        archive_path = os.path.join(ARCHIVE_DIR, name)
        assert os.path.isfile(archive_path), f"{name} is missing from the archive."
        assert stat.S_ISREG(os.lstat(archive_path).st_mode), f"{name} must be a regular file, not a link or special file."
        if kind == "json":
            with open(archive_path, "r", encoding="utf-8") as f:
                try:
                    actual_data = json.load(f)
                except json.JSONDecodeError:
                    assert False, f"{name} in archive is not valid JSON."
            assert actual_data == expected_data, f"Archived JSON {name} is not the exact required transformation."
        else:
            with open(archive_path, "r", encoding="utf-8", newline="") as f:
                actual_data = list(csv.reader(f))
            assert actual_data == expected_data, f"Archived CSV {name} is not the exact required transformation."

    file1_path = os.path.join(ARCHIVE_DIR, "file1.json")
    assert os.path.isfile(file1_path), "file1.json is missing from the archive."
    with open(file1_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert data.get("email") == "[REDACTED]", "Email in file1.json was not correctly redacted."
    assert "CONFIDENTIAL" in str(data), "Original CONFIDENTIAL data was lost in file1.json."

    file2_path = os.path.join(ARCHIVE_DIR, "file2.csv")
    assert os.path.isfile(file2_path), "file2.csv is missing from the archive."
    with open(file2_path, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, "file2.csv is empty."
    assert rows[0][1] == "[REDACTED]", "Email column in file2.csv was not correctly redacted."
    assert "CONFIDENTIAL" in "".join(rows[0]), "Original CONFIDENTIAL data was lost in file2.csv."

    file3_path = os.path.join(ARCHIVE_DIR, "file3.json")
    assert not os.path.exists(file3_path), "file3.json should not have been archived."


def expected_hashes():
    expected_files = build_expected_archive()
    return {name: get_file_sha256(os.path.join(ARCHIVE_DIR, name)) for name in expected_files}


def read_redis_manifest():
    try:
        output = subprocess.check_output(
            ["redis-cli", "--raw", "HGETALL", "archive_manifest"],
            text=True,
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to query Redis: {e.output}"
    lines = output.splitlines()
    assert len(lines) % 2 == 0, "Redis returned a malformed archive_manifest hash."
    return dict(zip(lines[0::2], lines[1::2]))


def test_redis_manifest_contains_correct_checksums():
    expected = expected_hashes()
    assert len(expected) == 2, "Expected 2 files to be archived for checksum verification."
    redis_manifest = read_redis_manifest()
    for name, expected_hash in expected.items():
        assert name in redis_manifest, f"{name} is missing from Redis archive_manifest."
        assert redis_manifest[name] == expected_hash, f"Redis checksum for {name} does not match the actual file's SHA-256."
    assert redis_manifest == expected, "Redis archive_manifest contains missing, extra, or incorrect entries."


def test_flask_api_manifest_endpoint():
    expected = expected_hashes()
    assert len(expected) == 2, "Expected 2 files to be archived for API verification."
    try:
        response = requests.get("http://127.0.0.1:5000/manifest", timeout=5)
    except requests.RequestException as e:
        assert False, f"Failed to connect to Flask API on port 5000: {e}"
    assert response.status_code == 200, f"Expected HTTP 200 from /manifest, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type to be application/json"
    try:
        api_manifest = response.json()
    except ValueError:
        assert False, "Response from /manifest is not valid JSON."
    for name, expected_hash in expected.items():
        assert name in api_manifest, f"{name} is missing from API /manifest response."
        assert api_manifest[name] == expected_hash, f"API checksum for {name} does not match the actual file's SHA-256."
    assert api_manifest == expected, "API manifest contains missing, extra, or incorrect entries."
    assert api_manifest == read_redis_manifest(), "API response is not the exact contents of the Redis hash."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
