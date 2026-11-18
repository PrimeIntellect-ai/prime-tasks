#!/bin/bash
mkdir -p /logs/verifier

# Ensure Redis is available for the submitted executable.
if ! redis-cli ping >/dev/null 2>&1; then
    redis-server --daemonize yes >/dev/null 2>&1 || true
    for _ in $(seq 1 100); do
        redis-cli ping >/dev/null 2>&1 && break
        sleep 0.05
    done
fi

# The image contains the validator but does not start it. Start it for the
# original validation-service assertion.
python3 /app/validator.py >/tmp/backup-validator.log 2>&1 &
VALIDATOR_PID=$!
trap 'kill "$VALIDATOR_PID" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 100); do
    if python3 -c 'import socket; s=socket.create_connection(("127.0.0.1",8080),0.05); s.close()' >/dev/null 2>&1; then
        break
    fi
    sleep 0.05
done

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tarfile
import time
import urllib.error
import urllib.request

import pytest
import redis

EXECUTABLE = "/home/user/fast_backup"
SOURCE = "/home/user/fast_backup.cpp"
RAW_DIR = "/home/user/raw_data"
TAR_PATH = "/home/user/backup.tar"
FILE_COUNT = 10000
FILE_SIZE = 1024


def test_executable_exists():
    assert os.path.isfile(SOURCE), f"C++ source {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"C++ source {SOURCE} is empty."

    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile your C++ code?"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."


def make_fresh_input():
    # Replace any agent-visible setup data with equivalent fresh, unpredictable
    # inputs so fabricated or precomputed output cannot satisfy the verifier.
    if os.path.lexists(RAW_DIR):
        if os.path.islink(RAW_DIR) or not os.path.isdir(RAW_DIR):
            os.unlink(RAW_DIR)
        else:
            shutil.rmtree(RAW_DIR)
    os.mkdir(RAW_DIR, 0o777)
    os.chmod(RAW_DIR, 0o777)

    expected_manifest = {}
    expected_hashes = {}
    original_stats = {}

    for i in range(FILE_COUNT):
        original = f"file_{i:04d}.dat"
        path = os.path.join(RAW_DIR, original)
        content = os.urandom(FILE_SIZE)
        with open(path, "wb") as f:
            f.write(content)
        os.chmod(path, 0o777)

        digest = hashlib.sha256(content).hexdigest()
        new_name = f"{digest}_{original}"
        expected_hashes[new_name] = digest
        expected_manifest[new_name] = {
            "original": original,
            "sha256": digest,
        }

        st = os.lstat(path)
        original_stats[original] = (
            st.st_dev,
            st.st_ino,
            stat.S_IFMT(st.st_mode),
            stat.S_IMODE(st.st_mode),
            st.st_uid,
            st.st_gid,
            st.st_size,
            st.st_mtime_ns,
            st.st_ctime_ns,
        )

    return expected_manifest, expected_hashes, original_stats


def assert_raw_data_unchanged(expected_manifest, original_stats):
    expected_originals = {v["original"] for v in expected_manifest.values()}
    assert set(os.listdir(RAW_DIR)) == expected_originals, "The executable changed the raw_data directory entries."

    for original in expected_originals:
        path = os.path.join(RAW_DIR, original)
        st = os.lstat(path)
        current_stat = (
            st.st_dev,
            st.st_ino,
            stat.S_IFMT(st.st_mode),
            stat.S_IMODE(st.st_mode),
            st.st_uid,
            st.st_gid,
            st.st_size,
            st.st_mtime_ns,
            st.st_ctime_ns,
        )
        assert current_stat == original_stats[original], f"Raw input metadata was modified: {original}"

        with open(path, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        expected_new_name = next(k for k, v in expected_manifest.items() if v["original"] == original)
        assert digest == expected_manifest[expected_new_name]["sha256"], f"Raw input content was modified: {original}"


def test_performance_and_correctness():
    expected_manifest, expected_hashes, original_stats = make_fresh_input()

    if os.path.exists(TAR_PATH):
        os.remove(TAR_PATH)

    try:
        r = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
        r.delete("backup:manifest")
    except Exception as e:
        pytest.fail(f"Failed to clear Redis key: {e}")

    start_time = time.perf_counter()
    try:
        result = subprocess.run(
            [EXECUTABLE], capture_output=True, text=True, timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Executable did not finish within 10 seconds.")
    elapsed = time.perf_counter() - start_time

    assert result.returncode == 0, (
        f"Executable failed with return code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )
    assert elapsed <= 2.0, f"Execution time {elapsed:.3f}s exceeded threshold of 2.0s."

    assert_raw_data_unchanged(expected_manifest, original_stats)

    manifest_str = r.get("backup:manifest")
    assert manifest_str is not None and manifest_str != "", "No manifest in Redis."
    try:
        manifest = json.loads(manifest_str)
    except Exception as e:
        pytest.fail(f"Redis manifest is not valid JSON: {e}")
    assert isinstance(manifest, dict), "Manifest must be a JSON object."
    assert manifest == expected_manifest, "Manifest does not exactly match the fresh raw_data inputs."

    assert os.path.isfile(TAR_PATH), "backup.tar not found."
    try:
        # r: accepts an uncompressed tar only, as required by the instruction.
        with tarfile.open(TAR_PATH, "r:") as tar:
            members = tar.getmembers()
            names = [member.name for member in members]
            assert len(members) == FILE_COUNT, "Tar must contain exactly 10,000 files."
            assert len(set(names)) == FILE_COUNT, "Tar contains duplicate member names."
            assert set(names) == set(expected_manifest), "Tar member names do not match the logical filenames."

            for member in members:
                assert member.isfile(), f"Tar member is not a regular file: {member.name}"
                assert member.size == FILE_SIZE, f"Incorrect archived size for {member.name}"
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Could not read archived file {member.name}"
                digest = hashlib.sha256(extracted.read()).hexdigest()
                assert digest == expected_hashes[member.name], f"Incorrect archived content for {member.name}"
    except tarfile.TarError as e:
        pytest.fail(f"backup.tar is not a valid uncompressed tar archive: {e}")

    # Retain the original validation-service assertion.
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/validate")
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
            assert data.get("status") == "success", f"Validation service reported failure: {data}"
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        pytest.fail(f"Validation service returned HTTP {e.code}: {error_body}")
    except Exception as e:
        pytest.fail(f"Failed to reach validation service or validate: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
