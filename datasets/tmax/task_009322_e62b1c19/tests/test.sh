#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import subprocess
import time
import uuid
import fcntl
import pytest
import ast

BASE_DIR = "/home/user/artifacts"
SCRIPT_PATH = "/home/user/indexer.py"
MANIFEST_PATH = "/home/user/manifest.json"
LOG_PATH = "/home/user/skipped_links.log"
PROBE = {}


def get_expected_data():
    expected = []
    files_info = [
        ("v1.0/app_v1.bin", "v1.0/app_v1.json"),
        ("v2.0/app_v2.bin", "v2.0/app_v2.json"),
        ("v2.0/sub_module/helper.bin", "v2.0/sub_module/helper.json")
    ]

    for bin_rel, json_rel in files_info:
        bin_path = os.path.join(BASE_DIR, bin_rel)
        json_path = os.path.join(BASE_DIR, json_rel)

        with open(bin_path, "rb") as f:
            sha256 = hashlib.sha256(f.read()).hexdigest()

        with open(json_path, "r") as f:
            meta = json.load(f)

        expected.append({
            "artifact_path": bin_path,
            "sha256": sha256,
            "name": meta["name"],
            "version": meta["version"]
        })

    return expected


def run_indexer(timeout=8):
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("indexer.py did not terminate; traversal may be following a symlink loop")
    assert result.returncode == 0, (
        f"indexer.py exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def prepare_and_execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"

    token = uuid.uuid4().hex
    probe_dir = os.path.join(BASE_DIR, f"verification_{token}", "nested", "deeper")
    os.makedirs(probe_dir)

    stem = f"artifact_{token}"
    bin_path = os.path.join(probe_dir, stem + ".bin")
    json_path = os.path.join(probe_dir, stem + ".json")
    payload = os.urandom(193) + token.encode("ascii")
    metadata = {"name": f"Dynamic-{token}", "version": f"9.{len(token)}"}

    with open(bin_path, "wb") as f:
        f.write(payload)
    with open(json_path, "w") as f:
        json.dump(metadata, f)

    loop_path = os.path.join(probe_dir, f"back_to_root_{token}")
    os.symlink(BASE_DIR, loop_path)

    PROBE.update({
        "bin_path": bin_path,
        "sha256": hashlib.sha256(payload).hexdigest(),
        "name": metadata["name"],
        "version": metadata["version"],
        "loop_path": loop_path,
    })

    for path in (MANIFEST_PATH, LOG_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_indexer()


def test_indexer_script_exists_and_uses_fcntl():
    script_path = "/home/user/indexer.py"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"

    with open(script_path, "r") as f:
        content = f.read()

    assert "fcntl.flock" in content, "The script must use fcntl.flock to ensure concurrent-safe manifest writing."
    assert "LOCK_EX" in content, "The script must use LOCK_EX for exclusive locking."


def test_skipped_links_log():
    log_path = "/home/user/skipped_links.log"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 1, "The log file should contain at least one skipped symlink."

    valid_loops = [
        "/home/user/artifacts/v2.0/legacy_loop",
        "/home/user/artifacts/latest/legacy_loop"
    ]

    found_loop = any(loop in lines for loop in valid_loops)
    assert found_loop, f"The log file must contain the skipped infinite loop symlink. Found: {lines}"

    assert PROBE["loop_path"] in lines, (
        "The dynamically-created loop symlink was not logged as skipped. "
        f"Expected {PROBE['loop_path']}, found: {lines}"
    )


def test_manifest_json():
    manifest_path = "/home/user/manifest.json"
    assert os.path.isfile(manifest_path), f"Manifest file missing: {manifest_path}"

    with open(manifest_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest is not a valid JSON file.")

    assert isinstance(data, list), "Manifest must be a JSON array."

    expected_data = get_expected_data()
    expected_lookup = {os.path.realpath(item["artifact_path"]): item for item in expected_data}

    for entry in data:
        assert "artifact_path" in entry, "Missing 'artifact_path' in manifest entry."
        assert "sha256" in entry, "Missing 'sha256' in manifest entry."
        assert "name" in entry, "Missing 'name' in manifest entry."
        assert "version" in entry, "Missing 'version' in manifest entry."

        real_path = os.path.realpath(entry["artifact_path"])
        if real_path == os.path.realpath(PROBE["bin_path"]):
            continue
        assert real_path in expected_lookup, f"Unexpected artifact path in manifest: {entry['artifact_path']}"

        expected_item = expected_lookup[real_path]
        assert entry["sha256"] == expected_item["sha256"], f"Incorrect SHA256 for {entry['artifact_path']}"
        assert entry["name"] == expected_item["name"], f"Incorrect name for {entry['artifact_path']}"
        assert entry["version"] == expected_item["version"], f"Incorrect version for {entry['artifact_path']}"

    found_real_paths = {
        os.path.realpath(entry["artifact_path"])
        for entry in data
        if os.path.realpath(entry["artifact_path"]) in expected_lookup
    }
    assert found_real_paths == set(expected_lookup.keys()), "Not all expected artifacts are present in the manifest."


def test_dynamic_nested_artifact_was_discovered_and_hashed():
    with open(MANIFEST_PATH, "r") as f:
        data = json.load(f)

    matches = [
        entry for entry in data
        if os.path.realpath(entry.get("artifact_path", "")) == os.path.realpath(PROBE["bin_path"])
    ]
    assert matches, "The indexer did not discover the dynamically-created nested artifact."

    for entry in matches:
        assert set(entry.keys()) == {"artifact_path", "sha256", "name", "version"}, (
            f"Manifest entries must have the exact required keys: {entry}"
        )
        assert os.path.isabs(entry["artifact_path"]), "artifact_path must be absolute."
        assert entry["sha256"] == PROBE["sha256"], "Dynamic artifact SHA256 is incorrect."
        assert entry["name"] == PROBE["name"], "Dynamic artifact name is incorrect."
        assert entry["version"] == PROBE["version"], "Dynamic artifact version is incorrect."


def test_indexer_actually_takes_exclusive_lock_on_manifest():
    with open(MANIFEST_PATH, "a+") as held_manifest:
        fcntl.flock(held_manifest.fileno(), fcntl.LOCK_EX)
        proc = subprocess.Popen(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            time.sleep(0.5)
            assert proc.poll() is None, (
                "indexer.py completed while another process held an exclusive lock "
                "on manifest.json; it did not actually use the required output-file lock"
            )
        finally:
            fcntl.flock(held_manifest.fileno(), fcntl.LOCK_UN)

        try:
            stdout, stderr = proc.communicate(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            pytest.fail("indexer.py did not finish after the manifest lock was released")
        assert proc.returncode == 0, (
            f"indexer.py failed after lock release\nstdout:\n{stdout}\nstderr:\n{stderr}"
        )


def test_concurrent_executions_leave_complete_valid_manifest():
    processes = [
        subprocess.Popen(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        for _ in range(3)
    ]

    for proc in processes:
        try:
            stdout, stderr = proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            pytest.fail("A concurrent indexer process did not terminate")
        assert proc.returncode == 0, (
            f"Concurrent indexer failed\nstdout:\n{stdout}\nstderr:\n{stderr}"
        )

    with open(MANIFEST_PATH, "r") as f:
        data = json.load(f)
    assert isinstance(data, list), "Concurrent runs left a non-array manifest."

    probe_entries = [
        entry for entry in data
        if os.path.realpath(entry.get("artifact_path", "")) == os.path.realpath(PROBE["bin_path"])
    ]
    assert probe_entries, "Concurrent runs left an incomplete manifest."
    assert all(entry.get("sha256") == PROBE["sha256"] for entry in probe_entries)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
