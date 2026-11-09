#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import tarfile
import hashlib
import pytest
import tempfile
import shutil
import subprocess
import secrets
import ctypes
import struct


def test_go_script_exists():
    assert os.path.isfile("/home/user/process_configs.go"), "Go script /home/user/process_configs.go does not exist."


def test_processed_json_files():
    expected_files = {
        "frontend_v1.0.4.json": {"service": "frontend", "version": "1.0.4", "port": 3000, "features": ["auth", "dashboard"]},
        "database_v13.2.json": {"service": "database", "version": "13.2", "max_connections": 100},
        "redis_cache_v6.2.0.json": {"service": "redis_cache", "version": "6.2.0", "max_memory": "4gb"}
    }

    processed_dir = "/home/user/processed_configs"
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} does not exist."

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(processed_dir, filename)
        assert os.path.isfile(filepath), f"Expected processed file {filepath} is missing."

        with open(filepath, 'r') as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"File {filepath} is not valid JSON.")

        assert "debug_token" not in data, f"debug_token was not removed from {filename}."

        for key, val in expected_content.items():
            assert key in data, f"Key '{key}' is missing in {filename}."
            assert data[key] == val, f"Value for '{key}' in {filename} is incorrect."


def test_manifest_checksums():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    processed_dir = "/home/user/processed_configs"

    with open(manifest_path, 'r') as f:
        manifest_lines = f.read().strip().splitlines()

    manifest_hashes = {}
    for line in manifest_lines:
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            manifest_hashes[parts[1].strip()] = parts[0].strip()

    expected_files = ["frontend_v1.0.4.json", "database_v13.2.json", "redis_cache_v6.2.0.json"]
    for filename in expected_files:
        filepath = os.path.join(processed_dir, filename)
        assert os.path.isfile(filepath), f"Missing file {filepath} for checksum validation."

        with open(filepath, 'rb') as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()

        found = False
        for manifest_file, manifest_hash in manifest_hashes.items():
            if os.path.basename(manifest_file) == filename:
                assert manifest_hash == actual_hash, f"Checksum mismatch for {filename} in manifest."
                found = True
                break
        assert found, f"File {filename} not found in manifest.txt."


def test_final_archive():
    archive_path = "/home/user/final_configs.tar.gz"
    assert os.path.isfile(archive_path), f"Final archive {archive_path} is missing."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            names = tar.getnames()

            assert any(os.path.basename(n) == "manifest.txt" for n in names), "manifest.txt missing from final archive."

            expected_files = ["frontend_v1.0.4.json", "database_v13.2.json", "redis_cache_v6.2.0.json"]
            for expected_file in expected_files:
                assert any(os.path.basename(n) == expected_file for n in names), f"{expected_file} missing from final archive."

            expected_contents = {
                "manifest.txt": open("/home/user/manifest.txt", "rb").read()
            }
            for expected_file in expected_files:
                with open(os.path.join("/home/user/processed_configs", expected_file), "rb") as f:
                    expected_contents[expected_file] = f.read()

            for basename, expected_data in expected_contents.items():
                matching_members = [m for m in tar.getmembers() if m.isfile() and os.path.basename(m.name) == basename]
                assert matching_members, f"Regular file {basename} missing from final archive."
                archived_data = [tar.extractfile(m).read() for m in matching_members]
                assert expected_data in archived_data, f"Archived content for {basename} does not match the produced file."

    except tarfile.ReadError:
        pytest.fail(f"Failed to read {archive_path}. It may not be a valid tar.gz file.")


def test_go_program_on_derived_inputs_and_atomic_writes():
    configs_dir = "/home/user/configs"
    processed_dir = "/home/user/processed_configs"

    shutil.rmtree(configs_dir, ignore_errors=True)
    shutil.rmtree(processed_dir, ignore_errors=True)
    os.makedirs(configs_dir)
    os.makedirs(processed_dir)

    nonce = secrets.token_hex(6)
    inputs = {
        f"arbitrary_{nonce}.json": {
            "service": f"audit_service_{nonce}",
            "version": f"9.{int(nonce[:2], 16)}.7",
            "debug_token": f"secret-{secrets.token_hex(10)}",
            "enabled": True,
            "limits": {"workers": 7, "labels": ["alpha", "beta"]}
        },
        f"unrelated_name_{nonce}.json": {
            "service": f"secondary_{nonce}",
            "version": "2.5.1",
            "count": 43,
            "message": "runtime-derived input"
        }
    }

    expected = {}
    for source_name, value in inputs.items():
        with open(os.path.join(configs_dir, source_name), "w") as f:
            json.dump(value, f)
        sanitized = dict(value)
        sanitized.pop("debug_token", None)
        expected[f"{value['service']}_v{value['version']}.json"] = sanitized

    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_init1.restype = ctypes.c_int
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    inotify_add_watch.restype = ctypes.c_int

    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    fd = inotify_init1(os.O_NONBLOCK)
    assert fd >= 0, "Could not initialize inotify for atomic-write verification."
    wd = inotify_add_watch(fd, processed_dir.encode(), IN_MOVED_FROM | IN_MOVED_TO)
    assert wd >= 0, "Could not watch processed_configs for atomic renames."

    try:
        result = subprocess.run(
            ["go", "run", "/home/user/process_configs.go"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60
        )

        assert result.returncode == 0, (
            "The Go program did not execute successfully.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        events = []
        while True:
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                break
            if not chunk:
                break
            offset = 0
            while offset + 16 <= len(chunk):
                event_wd, mask, cookie, name_len = struct.unpack_from("iIII", chunk, offset)
                offset += 16
                raw_name = chunk[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                events.append((mask, cookie, name))
    finally:
        os.close(fd)

    actual_files = {n for n in os.listdir(processed_dir) if os.path.isfile(os.path.join(processed_dir, n))}
    assert actual_files == set(expected), (
        f"Go program produced the wrong output files: expected {set(expected)}, got {actual_files}."
    )

    for filename, expected_data in expected.items():
        with open(os.path.join(processed_dir, filename), "r") as f:
            try:
                actual_data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"Runtime output {filename} is not valid JSON.")
        assert actual_data == expected_data, f"Runtime output {filename} was not correctly sanitized."
        assert "debug_token" not in actual_data, f"debug_token remains in runtime output {filename}."

    moved_from = {}
    moved_to = {}
    for mask, cookie, name in events:
        if mask & IN_MOVED_FROM:
            moved_from[cookie] = name
        if mask & IN_MOVED_TO:
            moved_to.setdefault(name, []).append(cookie)

    for filename in expected:
        cookies = moved_to.get(filename, [])
        assert cookies, f"{filename} was not atomically renamed into place."
        assert any(cookie in moved_from and moved_from[cookie] != filename for cookie in cookies), (
            f"{filename} was not written to a temporary file in processed_configs and atomically renamed."
        )


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
