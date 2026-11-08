#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hashlib
import pytest

LEGACY_REPO = "/home/user/legacy_repo"
CLEAN_CSV = "/home/user/clean_metadata.csv"
CURATE_PY = "/home/user/curate.py"
CURATED_REPO = "/home/user/curated_repo"
REGISTRY_JSON = "/home/user/curated_repo/registry.json"
LARGE_BLOBS_TXT = "/home/user/large_blobs.txt"

EXPECTED_DATA = [
    {"id": "ART-001", "name": "CoreEngine", "version": "1.0.0", "blob_file": "blob_A.blob"},
    {"id": "ART-002", "name": "PhysicsModule", "version": "1.2.4", "blob_file": "blob_B.blob"},
    {"id": "ART-003", "name": "RenderPip", "version": "2.1.0", "blob_file": "blob_C.blob"},
    {"id": "ART-004", "name": "AudioSys", "version": "3.0.1", "blob_file": "blob_D.blob"},
]

def get_legacy_blobs_info():
    blobs_info = {}
    for item in EXPECTED_DATA:
        blob_path = os.path.join(LEGACY_REPO, item["blob_file"])
        if os.path.exists(blob_path):
            with open(blob_path, "rb") as f:
                content = f.read()
            sha384_hash = hashlib.sha384(content).hexdigest()
            size = len(content)
            blobs_info[item["id"]] = {
                "name": item["name"],
                "version": item["version"],
                "sha384": sha384_hash,
                "size": size,
                "curated_path": os.path.join(CURATED_REPO, sha384_hash[:2], f"{sha384_hash}.blob")
            }
    return blobs_info

def test_curate_script_exists():
    assert os.path.isfile(CURATE_PY), f"Python script {CURATE_PY} does not exist."

def test_clean_metadata_csv():
    assert os.path.isfile(CLEAN_CSV), f"Clean metadata file {CLEAN_CSV} does not exist."

    with open(CLEAN_CSV, "rb") as f:
        content = f.read()

    assert b"\r" not in content, "Clean metadata file still contains carriage returns (CRLF)."
    assert b"|" not in content, "Clean metadata file still contains pipe delimiters."
    assert b"<b>" not in content and b"</b>" not in content, "Clean metadata file still contains HTML bold tags."

    lines = content.decode("utf-8").strip().split("\n")
    assert len(lines) == 5, f"Expected 5 lines in clean metadata, found {len(lines)}."
    assert lines[0] == "id,name,version,blob_file", "Header in clean metadata is incorrect."

    expected_lines = [
        "ART-001,CoreEngine,1.0.0,blob_A.blob",
        "ART-002,PhysicsModule,1.2.4,blob_B.blob",
        "ART-003,RenderPip,2.1.0,blob_C.blob",
        "ART-004,AudioSys,3.0.1,blob_D.blob"
    ]
    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in clean metadata."

def test_registry_json_and_curated_files():
    assert os.path.isfile(REGISTRY_JSON), f"Registry file {REGISTRY_JSON} does not exist."

    with open(REGISTRY_JSON, "r", encoding="utf-8") as f:
        try:
            registry = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Registry file is not valid JSON.")

    assert isinstance(registry, list), "Registry JSON must be an array."
    assert len(registry) == 4, f"Expected 4 items in registry, found {len(registry)}."

    blobs_info = get_legacy_blobs_info()
    assert len(blobs_info) == 4, "Legacy blobs are missing; cannot verify."
    assert {item.get("id") for item in registry} == set(blobs_info), "Registry must contain each expected artifact ID exactly once."

    for item in registry:
        assert set(item.keys()) == {"id", "name", "version", "sha384", "curated_path"}, "Registry item must have exactly the required keys."
        item_id = item["id"]
        assert item_id in blobs_info, f"Unknown id {item_id} in registry."

        expected = blobs_info[item_id]
        assert item.get("name") == expected["name"], f"Incorrect name for {item_id}."
        assert item.get("version") == expected["version"], f"Incorrect version for {item_id}."
        assert item.get("sha384") == expected["sha384"], f"Incorrect sha384 for {item_id}."
        assert item.get("curated_path") == expected["curated_path"], f"Incorrect curated_path for {item_id}."

        curated_path = item["curated_path"]
        assert os.path.isfile(curated_path), f"Curated blob file {curated_path} does not exist."

        with open(curated_path, "rb") as f:
            content = f.read()
        with open(os.path.join(LEGACY_REPO, next(x["blob_file"] for x in EXPECTED_DATA if x["id"] == item_id)), "rb") as f:
            source_content = f.read()
        assert content == source_content, f"Curated blob {curated_path} does not match its source blob."
        assert hashlib.sha384(content).hexdigest() == expected["sha384"], f"Curated blob {curated_path} hash mismatch."

def test_large_blobs_txt():
    assert os.path.isfile(LARGE_BLOBS_TXT), f"Large blobs file {LARGE_BLOBS_TXT} does not exist."

    blobs_info = get_legacy_blobs_info()
    expected_large_paths = []
    for info in blobs_info.values():
        if info["size"] > 500:
            expected_large_paths.append(info["curated_path"])

    expected_large_paths.sort()

    with open(LARGE_BLOBS_TXT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_large_paths, f"Expected large blobs paths {expected_large_paths}, but got {lines}."
    for path in lines:
        assert os.path.isfile(path), f"Listed large blob {path} does not exist."
        assert os.path.getsize(path) > 500, f"Listed blob {path} is not strictly larger than 500 bytes."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
