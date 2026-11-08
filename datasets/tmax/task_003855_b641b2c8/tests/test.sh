#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import io
import os
import subprocess
import tempfile
import zipfile

import pytest
import requests

URL = "http://127.0.0.1:8000/process_config"


def get_hash(content: bytes) -> str:
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(content)
        tmp_name = tmp.name
    try:
        result = subprocess.run(
            ["/app/config_hasher", tmp_name],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    finally:
        os.remove(tmp_name)


def post_archive(initial_files, operations):
    wal_lines = []
    for command, filename, payload in operations:
        if command in ("CREATE", "APPEND"):
            encoded = base64.b64encode(payload).decode("ascii")
        else:
            encoded = "none"
        wal_lines.append(f"{command}|{filename}|{encoded}\n")

    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w") as zf:
        # Reverse insertion order so implementations cannot rely on archive order.
        for name in reversed(list(initial_files)):
            zf.writestr(name, initial_files[name])
        zf.writestr("update.wal", "".join(wal_lines))

    try:
        response = requests.post(
            URL,
            data=archive.getvalue(),
            headers={"Content-Type": "application/zip"},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to or read from {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. "
        f"Response: {response.text[:200]}"
    )
    assert response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() == "application/zip"
    return response.content


def expected_state(initial_files, operations):
    state = dict(initial_files)
    for command, filename, payload in operations:
        if command == "CREATE":
            state[filename] = payload
        elif command == "APPEND":
            if filename in state:
                state[filename] += payload
        elif command == "DELETE":
            state.pop(filename, None)
    return state


def assert_dynamic_response(response_bytes, expected):
    try:
        with zipfile.ZipFile(io.BytesIO(response_bytes), "r") as zf:
            regular_names = [name for name in zf.namelist() if not name.endswith("/")]
            assert "update.wal" not in regular_names
            assert set(regular_names) == set(expected) | {"hashes.txt"}, (
                f"Unexpected response members: {regular_names}"
            )
            for name, content in expected.items():
                assert zf.read(name) == content, f"Unexpected content for {name}"

            actual_hash_lines = zf.read("hashes.txt").decode("utf-8").splitlines()
            expected_hash_lines = [
                f"{name}: {get_hash(expected[name])}" for name in sorted(expected)
            ]
            assert actual_hash_lines == expected_hash_lines, (
                f"hashes.txt order/content mismatch. Got: {actual_hash_lines}, "
                f"Expected: {expected_hash_lines}"
            )
    except zipfile.BadZipFile:
        pytest.fail("Response body is not a valid ZIP archive")


def test_process_config_endpoint_and_multiple_random_requests():
    # Preserve the original fixed-case assertions.
    original_ops = [
        ("APPEND", "core.conf", b"port=9090"),
        ("CREATE", "new.json", b'{"key": "val"}'),
        ("DELETE", "old.txt", None),
    ]
    original_response = post_archive(
        {"core.conf": b"server=1\n", "old.txt": b"delete me"},
        original_ops,
    )

    try:
        with zipfile.ZipFile(io.BytesIO(original_response), "r") as zf:
            files = zf.namelist()
            assert "update.wal" not in files, "update.wal should have been deleted from the final archive"
            assert "core.conf" in files, "core.conf is missing from the response"
            assert "new.json" in files, "new.json is missing from the response"
            assert "old.txt" not in files, "old.txt should have been deleted"
            assert "hashes.txt" in files, "hashes.txt is missing from the response"

            core_conf = zf.read("core.conf")
            assert core_conf == b"server=1\nport=9090", f"Unexpected core.conf content: {core_conf}"
            new_json = zf.read("new.json")
            assert new_json == b'{"key": "val"}', f"Unexpected new.json content: {new_json}"

            hashes_txt = zf.read("hashes.txt").decode("utf-8").strip().split("\n")
            expected_lines = [
                f"core.conf: {get_hash(b'server=1\nport=9090')}",
                f"new.json: {get_hash(b'{\"key\": \"val\"}')}",
            ]
            assert sorted(hashes_txt) == sorted(expected_lines), (
                f"hashes.txt contents mismatch. Got: {hashes_txt}, Expected: {expected_lines}"
            )
    except zipfile.BadZipFile:
        pytest.fail("Response body is not a valid ZIP archive")

    # Runtime-randomized names and binary contents prevent a canned response.
    token = os.urandom(8).hex()
    keep = f"z-{token}.bin"
    append_name = f"configs/{token}/service.conf"
    delete_name = f"configs/{token}/obsolete.dat"
    overwrite_name = f"a-{token}/overwrite.json"
    created_name = f"m-{token}/new.bin"
    missing_name = f"missing-{token}.txt"

    initial = {
        keep: os.urandom(37),
        append_name: os.urandom(19),
        delete_name: os.urandom(13),
        overwrite_name: os.urandom(11),
    }
    operations = [
        ("APPEND", append_name, os.urandom(23)),
        ("APPEND", missing_name, os.urandom(17)),
        ("CREATE", overwrite_name, os.urandom(29)),
        ("CREATE", created_name, os.urandom(31)),
        ("APPEND", created_name, os.urandom(7)),
        ("DELETE", delete_name, None),
        ("DELETE", f"absent-{token}.dat", None),
    ]
    expected = expected_state(initial, operations)
    assert_dynamic_response(post_archive(initial, operations), expected)

    # A distinct sequential request also verifies that workspaces do not leak state.
    token2 = os.urandom(8).hex()
    only_name = f"second/{token2}/only.cfg"
    added_name = f"second/{token2}/added.cfg"
    initial2 = {only_name: os.urandom(41)}
    operations2 = [
        ("APPEND", only_name, os.urandom(9)),
        ("CREATE", added_name, os.urandom(27)),
    ]
    expected2 = expected_state(initial2, operations2)
    assert_dynamic_response(post_archive(initial2, operations2), expected2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
