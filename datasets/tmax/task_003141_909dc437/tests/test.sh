#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import json
import os
import subprocess
import tarfile
import time
import uuid as uuidlib

import pytest
import requests

BLOBS_DIR = "/home/user/archive/blobs"
INDEX_FILE = "/home/user/archive/master_index.jsonl"
UPLOAD_URL = "http://127.0.0.1:8080/upload"


def is_service_running(process_name: str) -> bool:
    try:
        output = subprocess.check_output(["ps", "aux"]).decode()
        return process_name in output
    except Exception:
        return False


def test_services_running():
    assert is_service_running("redis-server"), "Redis server is not running"
    assert is_service_running("nginx"), "Nginx is not running"
    assert is_service_running("intake.py") or is_service_running("flask"), "Flask API is not running"
    assert is_service_running("sanitizer.sh"), "Sanitizer worker is not running"


def test_nginx_config_updated():
    nginx_conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"Nginx config not found at {nginx_conf_path}"
    with open(nginx_conf_path, "r") as f:
        content = f.read()
    assert "client_max_body_size 20m;" in content.lower() or "client_max_body_size 20M;" in content, \
        "Nginx config was not updated to allow 20M uploads."


def test_flask_api_updated():
    api_path = "/app/api/intake.py"
    assert os.path.isfile(api_path), f"Flask API file not found at {api_path}"
    with open(api_path, "r") as f:
        content = f.read()
    assert "invalid-host" not in content, "Flask API still has 'invalid-host' in redis connection string."
    assert "127.0.0.1" in content or "localhost" in content, "Flask API redis host not updated correctly."


def add_member(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def make_archive(path, metadata=None, payload=None):
    with tarfile.open(path, "w") as tar:
        if metadata is not None:
            add_member(tar, "metadata.json", metadata)
        if payload is not None:
            add_member(tar, "payload.dat", payload)


def upload_file(filepath: str) -> str:
    try:
        with open(filepath, "rb") as f:
            response = requests.post(
                UPLOAD_URL,
                files={"file": (os.path.basename(filepath), f, "application/x-tar")},
                timeout=20,
            )
        if response.status_code != 200:
            return f"ERROR: {response.status_code}"
        try:
            uploaded_uuid = response.json().get("uuid", "")
            uuidlib.UUID(uploaded_uuid)
            return uploaded_uuid
        except Exception:
            return "ERROR: invalid or missing UUID"
    except Exception as exc:
        return f"ERROR: {exc}"


def test_corpus_processing(tmp_path):
    run_token = uuidlib.uuid4().hex
    clean_cases = []
    evil_cases = []

    for number, raw in enumerate((b"clean-one", os.urandom(4096))):
        marker = f"clean-{run_token}-{number}"
        metadata_obj = {"backup_type": "system_state", "case_id": marker}
        metadata = json.dumps(metadata_obj, separators=(",", ":")).encode() + b"\n"
        payload = gzip.compress(raw)
        archive = tmp_path / f"clean-{number}.tar"
        make_archive(archive, metadata, payload)
        clean_cases.append({
            "path": str(archive),
            "marker": marker,
            "metadata_line": metadata.decode().rstrip("\n"),
            "payload": payload,
        })

    valid_payload = gzip.compress(b"valid payload")

    marker = f"evil-{run_token}-missing-metadata"
    path = tmp_path / "evil-missing-metadata.tar"
    make_archive(path, None, valid_payload)
    evil_cases.append({"path": str(path), "marker": marker})

    marker = f"evil-{run_token}-invalid-json"
    path = tmp_path / "evil-invalid-json.tar"
    make_archive(path, (f'{{"case_id":"{marker}","backup_type":').encode(), valid_payload)
    evil_cases.append({"path": str(path), "marker": marker})

    marker = f"evil-{run_token}-wrong-type"
    path = tmp_path / "evil-wrong-type.tar"
    metadata = json.dumps({"backup_type": "user_data", "case_id": marker}, separators=(",", ":")).encode() + b"\n"
    make_archive(path, metadata, valid_payload)
    evil_cases.append({"path": str(path), "marker": marker})

    marker = f"evil-{run_token}-missing-payload"
    path = tmp_path / "evil-missing-payload.tar"
    metadata = json.dumps({"backup_type": "system_state", "case_id": marker}, separators=(",", ":")).encode() + b"\n"
    make_archive(path, metadata, None)
    evil_cases.append({"path": str(path), "marker": marker})

    marker = f"evil-{run_token}-bad-gzip"
    path = tmp_path / "evil-bad-gzip.tar"
    metadata = json.dumps({"backup_type": "system_state", "case_id": marker}, separators=(",", ":")).encode() + b"\n"
    make_archive(path, metadata, b"not a gzip payload")
    evil_cases.append({"path": str(path), "marker": marker})

    marker = f"evil-{run_token}-oversized"
    path = tmp_path / "evil-oversized.tar"
    metadata = json.dumps({"backup_type": "system_state", "case_id": marker}, separators=(",", ":")).encode() + b"\n"
    oversized_payload = gzip.compress(os.urandom(10485760))
    assert len(oversized_payload) > 10485760
    make_archive(path, metadata, oversized_payload)
    evil_cases.append({"path": str(path), "marker": marker})

    for case in clean_cases:
        uploaded_uuid = upload_file(case["path"])
        assert not uploaded_uuid.startswith("ERROR"), f"Failed to upload clean file {case['path']}: {uploaded_uuid}"
        case["uuid"] = uploaded_uuid

    for case in evil_cases:
        uploaded_uuid = upload_file(case["path"])
        assert not uploaded_uuid.startswith("ERROR"), f"Failed to upload evil file {case['path']}: {uploaded_uuid}"
        case["uuid"] = uploaded_uuid

    deadline = time.time() + 30
    while time.time() < deadline:
        clean_done = all(os.path.isfile(os.path.join(BLOBS_DIR, f"{case['uuid']}.gz")) for case in clean_cases)
        evil_done = all(not os.path.exists(os.path.join("/home/user/staging", case["uuid"])) for case in evil_cases)
        if clean_done and evil_done:
            break
        time.sleep(0.25)

    if os.path.exists(INDEX_FILE):
        with open(INDEX_FILE, "r", errors="replace") as f:
            index_content = f.read()
    else:
        index_content = ""
    index_lines = index_content.splitlines()

    clean_failed = []
    for case in clean_cases:
        blob_path = os.path.join(BLOBS_DIR, f"{case['uuid']}.gz")
        if not os.path.isfile(blob_path):
            clean_failed.append(os.path.basename(case["path"]))
        else:
            with open(blob_path, "rb") as f:
                if f.read() != case["payload"]:
                    clean_failed.append(os.path.basename(case["path"]) + " (payload modified)")
        if case["metadata_line"] not in index_lines:
            clean_failed.append(os.path.basename(case["path"]) + " (missing in index)")

    evil_bypassed = []
    for case in evil_cases:
        blob_path = os.path.join(BLOBS_DIR, f"{case['uuid']}.gz")
        staging_path = os.path.join("/home/user/staging", case["uuid"])
        if os.path.exists(blob_path) or case["marker"] in index_content or os.path.exists(staging_path):
            evil_bypassed.append(os.path.basename(case["path"]))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_cases)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} clean results modified/missing: {', '.join(clean_failed)}")

    assert not error_msgs, " | ".join(error_msgs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
