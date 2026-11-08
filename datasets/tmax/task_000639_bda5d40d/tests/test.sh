#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import xml.etree.ElementTree as ET

import cv2
import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
ARTIFACT_DIR = "/home/user/artifacts"


def decode_root_id():
    cap = cv2.VideoCapture("/app/deploy_sequence.mp4")
    assert cap.isOpened(), "Could not open deploy_sequence.mp4"
    value = 0
    try:
        for _ in range(16):
            ok, frame = cap.read()
            assert ok, "Video contains fewer than 16 frames"
            bit = 1 if float(frame.mean()) > 127 else 0
            value = (value << 1) | bit
    finally:
        cap.release()
    return value


ROOT_ID = str(decode_root_id())
HEADERS = {"Authorization": f"Bearer {ROOT_ID}"}


def make_bin(artifact_id, deps, name, version):
    xml = (
        f"<artifact><name>{name}</name>"
        f"<version>{version}</version></artifact>"
    ).encode("utf-8")
    return (
        b"ARTF"
        + struct.pack("<II", artifact_id, len(deps))
        + b"".join(struct.pack("<I", dep) for dep in deps)
        + struct.pack("<I", len(xml))
        + xml
    )


def write_artifact(artifact_id, deps, name, version):
    path = os.path.join(ARTIFACT_DIR, f"{artifact_id}.bin")
    tmp = path + ".verifier-tmp"
    with open(tmp, "wb") as f:
        f.write(make_bin(artifact_id, deps, name, version))
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def allocate_ids(count):
    result = []
    while len(result) < count:
        candidate = secrets.randbelow(2_000_000_000 - 100_000) + 100_000
        if candidate not in result and not os.path.exists(
            os.path.join(ARTIFACT_DIR, f"{candidate}.bin")
        ):
            result.append(candidate)
    return result


DYNAMIC_IDS = allocate_ids(5)
A, B, C, D, ISOLATED = DYNAMIC_IDS
TOKENS = [secrets.token_hex(10) for _ in DYNAMIC_IDS]

# This graph includes duplicate edges, shared dependencies, and cycles.
write_artifact(A, [B, C, B], f"root-{TOKENS[0]}", f"v-{TOKENS[0]}")
write_artifact(B, [D], f"branch-{TOKENS[1]}", f"v-{TOKENS[1]}")
write_artifact(C, [D, A], f"cycle-{TOKENS[2]}", f"v-{TOKENS[2]}")
write_artifact(D, [B], f"leaf-{TOKENS[3]}", f"v-{TOKENS[3]}")
write_artifact(ISOLATED, [], f"solo-{TOKENS[4]}", f"v-{TOKENS[4]}")


def oracle_parse(artifact_id):
    path = os.path.join(ARTIFACT_DIR, f"{artifact_id}.bin")
    with open(path, "rb") as f:
        data = f.read()
    assert data[:4] == b"ARTF"
    stored_id, count = struct.unpack_from("<II", data, 4)
    assert stored_id == artifact_id
    deps = list(struct.unpack_from(f"<{count}I", data, 12)) if count else []
    length_offset = 12 + 4 * count
    manifest_length = struct.unpack_from("<I", data, length_offset)[0]
    xml_start = length_offset + 4
    root = ET.fromstring(data[xml_start:xml_start + manifest_length])
    manifest = {child.tag: child.text or "" for child in root}
    return deps, manifest


def oracle_dependencies(start):
    seen = {start}
    pending = [start]
    while pending:
        current = pending.pop()
        deps, _ = oracle_parse(current)
        for dep in deps:
            if dep not in seen:
                seen.add(dep)
                pending.append(dep)
    seen.remove(start)
    return sorted(seen)


def get(path, headers=None):
    url = f"{BASE_URL}{path}"
    try:
        return requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service at {url}: {exc}")


# Preserve the original authentication assertions.
def test_auth_missing_header():
    response = get("/manifest/1001")
    assert response.status_code == 401, (
        f"Expected 401 for missing auth header, got {response.status_code}. "
        f"Response: {response.text}"
    )


def test_auth_invalid_header():
    response = get("/manifest/1001", {"Authorization": "Bearer 9999"})
    assert response.status_code == 401, (
        f"Expected 401 for invalid auth header, got {response.status_code}. "
        f"Response: {response.text}"
    )


# Preserve the original known-fixture manifest assertion.
def test_manifest_parsing():
    response = get("/manifest/43981", HEADERS)
    assert response.status_code == 200, (
        f"Expected 200 for valid manifest request, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    expected_data = {"name": "root-app", "version": "1.0"}
    assert data == expected_data, f"Expected JSON {expected_data}, got {data}"


# Preserve the original known-fixture traversal assertion.
def test_dependency_traversal():
    response = get("/dependencies/43981", HEADERS)
    assert response.status_code == 200, (
        f"Expected 200 for valid dependency request, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    expected_data = [1001, 1002, 1003]
    assert data == expected_data, f"Expected JSON {expected_data}, got {data}"


def test_dynamic_manifests_are_parsed_from_binary_files():
    for artifact_id in DYNAMIC_IDS:
        response = get(f"/manifest/{artifact_id}", HEADERS)
        assert response.status_code == 200, response.text
        _, expected = oracle_parse(artifact_id)
        assert response.json() == expected


def test_dynamic_recursive_traversal_and_cycles():
    for artifact_id in (A, B, C, ISOLATED):
        response = get(f"/dependencies/{artifact_id}", HEADERS)
        assert response.status_code == 200, response.text
        assert response.json() == oracle_dependencies(artifact_id)


def test_authentication_is_required_on_dependencies():
    missing = get(f"/dependencies/{A}")
    assert missing.status_code == 401, missing.text

    wrong_value = str((int(ROOT_ID) + 1) % 65536)
    invalid = get(
        f"/dependencies/{A}",
        {"Authorization": f"Bearer {wrong_value}"},
    )
    assert invalid.status_code == 401, invalid.text


def test_unknown_manifest_returns_404():
    unknown = allocate_ids(1)[0]
    response = get(f"/manifest/{unknown}", HEADERS)
    assert response.status_code == 404, response.text
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
