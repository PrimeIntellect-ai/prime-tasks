#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import hashlib
import io
import json
import os
import runpy
import shutil
import uuid

import pytest

SCRIPT_PATH = "/home/user/organize.py"
MANIFEST_PATH = "/home/user/organized_files/manifest.json"
TMP_MANIFEST_PATH = "/home/user/organized_files/manifest.json.tmp"
PROJECT_ROOT = "/home/user/project_files"
ORGANIZED_ROOT = "/home/user/organized_files"

EXPECTED_FILES = {
    "elf": [
        "/home/user/project_files/builds/v1/firmware_v1.bin",
        "/home/user/project_files/builds/v2/fw_v2_final.out"
    ],
    "gcode": [
        "/home/user/project_files/models/bracket.gcode",
        "/home/user/project_files/models/gear.gcode"
    ]
}


def compute_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def test_manifest_exists_and_tmp_does_not():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"
    assert not os.path.exists(TMP_MANIFEST_PATH), f"Temporary manifest file {TMP_MANIFEST_PATH} should have been renamed or removed."


def test_manifest_content_and_symlinks():
    assert os.path.isfile(MANIFEST_PATH), "Manifest file missing"

    with open(MANIFEST_PATH, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest is not valid JSON")

    assert isinstance(manifest, dict), "Manifest should be a JSON dictionary"

    expected_manifest = {}
    for category, paths in EXPECTED_FILES.items():
        for path in paths:
            assert os.path.isfile(path), f"Original file missing: {path}"
            checksum = compute_sha256(path)
            prefix = checksum[:8]
            filename = os.path.basename(path)
            symlink_name = f"{filename}_{prefix}"
            symlink_path = f"/home/user/organized_files/{category}/{symlink_name}"

            expected_manifest[symlink_path] = {
                "original_path": path,
                "checksum": checksum
            }

    assert set(manifest.keys()) == set(expected_manifest.keys()), \
        f"Manifest keys do not match expected symlink paths. Expected: {list(expected_manifest.keys())}, Got: {list(manifest.keys())}"

    for symlink_path, expected_data in expected_manifest.items():
        actual_data = manifest[symlink_path]

        assert actual_data.get("original_path") == expected_data["original_path"], \
            f"Incorrect original_path in manifest for {symlink_path}"
        assert actual_data.get("checksum") == expected_data["checksum"], \
            f"Incorrect checksum in manifest for {symlink_path}"

        assert os.path.islink(symlink_path), f"Expected a symbolic link at {symlink_path}"

        target = os.readlink(symlink_path)
        assert target == expected_data["original_path"], \
            f"Symlink {symlink_path} points to {target}, expected {expected_data['original_path']}"


def derive_expected_manifest():
    expected = {}
    for root, _, files in os.walk(PROJECT_ROOT):
        for filename in files:
            path = os.path.abspath(os.path.join(root, filename))
            with open(path, "rb") as f:
                first_four = f.read(4)

            category = None
            if first_four == b"\x7fELF":
                category = "elf"
            elif filename.endswith(".gcode") and first_four[:1] in (b";", b"G"):
                category = "gcode"

            if category is None:
                continue

            checksum = compute_sha256(path)
            link_path = os.path.join(
                ORGANIZED_ROOT, category, f"{filename}_{checksum[:8]}"
            )
            expected[link_path] = {
                "original_path": path,
                "checksum": checksum,
            }
    return expected


def test_script_executes_on_new_inputs_and_writes_manifest_atomically():
    assert os.path.isfile(SCRIPT_PATH), f"Required script is missing: {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "organize.py must be an actual script, not a symlink"

    token = uuid.uuid4().hex
    probe_dir = os.path.join(PROJECT_ROOT, "verification_" + token, "nested")
    os.makedirs(probe_dir, exist_ok=True)

    probe_files = {
        f"dynamic_{token}.blob": b"\x7fELF" + os.urandom(53),
        f"dynamic_{token}.gcode": b"; verifier-generated toolpath\nG1 X17 Y29\n" + os.urandom(19),
        f"ignored_{token}.gcode": b"X this must not be treated as gcode\n",
        f"ignored_{token}.txt": b"G1 X1 Y1\n",
    }
    for name, data in probe_files.items():
        with open(os.path.join(probe_dir, name), "wb") as f:
            f.write(data)

    expected_manifest = derive_expected_manifest()

    shutil.rmtree(ORGANIZED_ROOT, ignore_errors=True)

    events = []
    tmp_fds = set()
    real_builtin_open = builtins.open
    real_io_open = io.open
    real_fsync = os.fsync
    real_rename = os.rename
    real_replace = os.replace

    class TrackedFile:
        def __init__(self, wrapped):
            self._wrapped = wrapped
            tmp_fds.add(wrapped.fileno())

        def flush(self):
            events.append("flush")
            return self._wrapped.flush()

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return self._wrapped.__exit__(exc_type, exc, tb)

        def __iter__(self):
            return iter(self._wrapped)

        def __getattr__(self, name):
            return getattr(self._wrapped, name)

    def should_track(file, mode):
        try:
            path = os.path.abspath(os.fspath(file))
        except TypeError:
            return False
        return path == TMP_MANIFEST_PATH and any(flag in mode for flag in "wax+")

    def tracked_builtin_open(file, mode="r", *args, **kwargs):
        wrapped = real_builtin_open(file, mode, *args, **kwargs)
        return TrackedFile(wrapped) if should_track(file, mode) else wrapped

    def tracked_io_open(file, mode="r", *args, **kwargs):
        wrapped = real_io_open(file, mode, *args, **kwargs)
        return TrackedFile(wrapped) if should_track(file, mode) else wrapped

    def tracked_fsync(fd):
        if fd in tmp_fds:
            events.append("fsync")
        return real_fsync(fd)

    def paths_are_manifest_move(src, dst):
        try:
            return (os.path.abspath(os.fspath(src)) == TMP_MANIFEST_PATH and
                    os.path.abspath(os.fspath(dst)) == MANIFEST_PATH)
        except TypeError:
            return False

    def tracked_rename(src, dst, *args, **kwargs):
        result = real_rename(src, dst, *args, **kwargs)
        if paths_are_manifest_move(src, dst):
            events.append("rename")
        return result

    def tracked_replace(src, dst, *args, **kwargs):
        result = real_replace(src, dst, *args, **kwargs)
        if paths_are_manifest_move(src, dst):
            events.append("rename")
        return result

    builtins.open = tracked_builtin_open
    io.open = tracked_io_open
    os.fsync = tracked_fsync
    os.rename = tracked_rename
    os.replace = tracked_replace
    try:
        try:
            runpy.run_path(SCRIPT_PATH, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"organize.py exited with status {exc.code}"
    finally:
        builtins.open = real_builtin_open
        io.open = real_io_open
        os.fsync = real_fsync
        os.rename = real_rename
        os.replace = real_replace

    assert os.path.isfile(MANIFEST_PATH), "Executing organize.py did not create manifest.json"
    assert not os.path.exists(TMP_MANIFEST_PATH), "Temporary manifest remained after execution"

    with real_builtin_open(MANIFEST_PATH, "r") as f:
        manifest = json.load(f)
    assert manifest == expected_manifest, "Script output did not match recursively discovered files"

    for link_path, data in expected_manifest.items():
        assert os.path.islink(link_path), f"Missing generated symlink: {link_path}"
        assert os.readlink(link_path) == data["original_path"], \
            f"Incorrect target for generated symlink: {link_path}"

    assert "flush" in events, "manifest.json.tmp was not explicitly flushed"
    assert "fsync" in events, "manifest.json.tmp was not synced with os.fsync"
    assert "rename" in events, "manifest.json.tmp was not renamed to manifest.json"
    assert events.index("flush") < events.index("fsync") < events.index("rename"), \
        f"Atomic manifest operations occurred in the wrong order: {events}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
