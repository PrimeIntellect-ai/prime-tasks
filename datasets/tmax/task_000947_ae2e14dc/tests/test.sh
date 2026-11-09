#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_config_manager.py
import ctypes
import errno
import hashlib
import json
import os
import select
import struct
import subprocess
import time
import uuid

import pytest


def test_go_source_code_exists_and_atomic_ops():
    go_file = "/home/user/config_manager.go"
    assert os.path.isfile(go_file), f"Go source file missing at {go_file}"

    with open(go_file, "r") as f:
        content = f.read()

    assert "os.Rename" in content, "Go code must use os.Rename for atomic operations"
    assert "os.Symlink" in content, "Go code must use os.Symlink for creating the symlink"


def test_snapshot_directory_exists():
    snapshot_dir = "/home/user/snapshots/my_run"
    assert os.path.isdir(snapshot_dir), f"Snapshot directory missing at {snapshot_dir}"


def test_current_symlink():
    symlink_path = "/home/user/snapshots/current"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"

    target = os.path.realpath(symlink_path)
    expected_target = os.path.realpath("/home/user/snapshots/my_run")
    assert target == expected_target, f"Symlink points to {target}, expected {expected_target}"


def test_hard_links():
    snapshot_dir = "/home/user/snapshots/my_run"

    expected_links = {
        "app1_db.conf": "/home/user/etc_mock/app1/db.conf",
        "nginx_nginx.conf": "/home/user/etc_mock/nginx/nginx.conf"
    }

    for snap_file, orig_file in expected_links.items():
        snap_path = os.path.join(snapshot_dir, snap_file)
        assert os.path.isfile(snap_path), f"Hard link missing: {snap_path}"

        orig_stat = os.stat(orig_file)
        snap_stat = os.stat(snap_path)

        assert orig_stat.st_ino == snap_stat.st_ino, f"File {snap_path} is not a hard link to {orig_file} (inodes differ)"
        assert orig_stat.st_dev == snap_stat.st_dev, f"File {snap_path} and {orig_file} are on different devices"


def test_filtered_files_not_present():
    snapshot_dir = "/home/user/snapshots/my_run"

    unexpected_files = [
        "app1_old.conf",
        "old_root.conf",
        "nginx_not_a_conf.txt",
        "not_a_conf.txt"
    ]

    for f in unexpected_files:
        path = os.path.join(snapshot_dir, f)
        assert not os.path.exists(path), f"Filtered file should not be in snapshot: {path}"


def test_manifest_json():
    manifest_path = "/home/user/snapshots/my_run/manifest.json"
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest file is not valid JSON")

    expected_files = [
        "/home/user/etc_mock/app1/db.conf",
        "/home/user/etc_mock/nginx/nginx.conf"
    ]

    assert len(manifest) == len(expected_files), f"Manifest should contain exactly {len(expected_files)} keys"

    for orig_file in expected_files:
        assert orig_file in manifest, f"Manifest is missing key for {orig_file}"

        with open(orig_file, "rb") as f:
            file_bytes = f.read()
            expected_checksum = hashlib.sha256(file_bytes).hexdigest()

        assert manifest[orig_file] == expected_checksum, f"Checksum mismatch for {orig_file}"


def _eligible_files(cutoff):
    root = "/home/user/etc_mock"
    result = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for filename in filenames:
            path = os.path.join(dirpath, filename)
            if not filename.endswith(".conf") or not os.path.isfile(path):
                continue
            st = os.stat(path)
            if st.st_mtime >= cutoff:
                with open(path, "rb") as f:
                    checksum = hashlib.sha256(f.read()).hexdigest()
                rel = os.path.relpath(path, root)
                flat = rel.replace(os.sep, "_")
                assert flat not in result, f"Test input has a flattened-name collision: {flat}"
                result[flat] = (path, checksum, st.st_dev, st.st_ino)
    return result


def test_program_executes_on_fresh_dynamic_input_and_snapshot_name():
    token = uuid.uuid4().hex
    nested_dir = os.path.join("/home/user/etc_mock", "audit_" + token, "deeper")
    os.makedirs(nested_dir, mode=0o777)
    os.chmod(os.path.dirname(nested_dir), 0o777)
    os.chmod(nested_dir, 0o777)

    recent_nested = os.path.join(nested_dir, "dynamic_" + token + ".conf")
    recent_root = os.path.join("/home/user/etc_mock", "root_" + token + ".conf")
    old_conf = os.path.join(nested_dir, "old_" + token + ".conf")
    ignored = os.path.join(nested_dir, "ignored_" + token + ".txt")

    contents = {
        recent_nested: ("dynamic nested value " + token + "\n").encode(),
        recent_root: ("dynamic root value " + token + "\n").encode(),
        old_conf: ("old value " + token + "\n").encode(),
        ignored: ("not a conf " + token + "\n").encode(),
    }
    for path, data in contents.items():
        with open(path, "wb") as f:
            f.write(data)
        os.chmod(path, 0o644)
    old_time = time.time() - 49 * 60 * 60
    os.utime(old_conf, (old_time, old_time))

    cutoff = time.time() - 24 * 60 * 60
    expected = _eligible_files(cutoff)
    assert os.path.relpath(recent_nested, "/home/user/etc_mock").replace(os.sep, "_") in expected
    assert os.path.relpath(recent_root, "/home/user/etc_mock").replace(os.sep, "_") in expected
    assert os.path.relpath(old_conf, "/home/user/etc_mock").replace(os.sep, "_") not in expected

    snapshot_name = "audit_" + token
    snapshot_dir = os.path.join("/home/user/snapshots", snapshot_name)
    assert not os.path.lexists(snapshot_dir)

    # Watch the snapshots directory. An atomic replacement of current by rename
    # produces IN_MOVED_TO for the name "current".
    libc = ctypes.CDLL(None, use_errno=True)
    IN_NONBLOCK = os.O_NONBLOCK
    IN_CLOEXEC = os.O_CLOEXEC
    IN_MOVED_TO = 0x00000080
    fd = libc.inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
    assert fd >= 0, os.strerror(ctypes.get_errno())
    wd = libc.inotify_add_watch(fd, b"/home/user/snapshots", IN_MOVED_TO)
    assert wd >= 0, os.strerror(ctypes.get_errno())

    cmd = [
        "runuser", "-u", "user", "--", "env",
        "HOME=/home/user", "GOCACHE=/tmp/config-manager-go-cache",
        "go", "run", "/home/user/config_manager.go", snapshot_name,
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    events = []

    def drain_events():
        while True:
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                return
            if not data:
                return
            offset = 0
            while offset + 16 <= len(data):
                event_wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
                events.append((mask, name))

    deadline = time.time() + 60
    while proc.poll() is None and time.time() < deadline:
        drain_events()
        time.sleep(0.002)
    if proc.poll() is None:
        proc.kill()
        stdout, stderr = proc.communicate()
        os.close(fd)
        pytest.fail(f"config_manager.go timed out\nstdout:\n{stdout}\nstderr:\n{stderr}")
    stdout, stderr = proc.communicate()
    drain_events()
    os.close(fd)

    assert proc.returncode == 0, (
        f"go run failed with status {proc.returncode}\nstdout:\n{stdout}\nstderr:\n{stderr}"
    )
    assert any(mask & IN_MOVED_TO and name == "current" for mask, name in events), (
        "current was not atomically installed using a rename into place"
    )

    assert os.path.isdir(snapshot_dir), f"Fresh snapshot directory missing: {snapshot_dir}"
    assert os.path.islink("/home/user/snapshots/current")
    assert os.path.realpath("/home/user/snapshots/current") == os.path.realpath(snapshot_dir)

    actual_entries = set(os.listdir(snapshot_dir))
    expected_entries = set(expected) | {"manifest.json"}
    assert actual_entries == expected_entries, (
        f"Snapshot entries differ: expected {sorted(expected_entries)}, got {sorted(actual_entries)}"
    )

    manifest_path = os.path.join(snapshot_dir, "manifest.json")
    assert os.path.isfile(manifest_path)
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
    expected_manifest = {path: checksum for path, checksum, dev, ino in expected.values()}
    assert manifest == expected_manifest

    for flat_name, (original, checksum, original_dev, original_ino) in expected.items():
        linked = os.path.join(snapshot_dir, flat_name)
        linked_stat = os.stat(linked)
        assert linked_stat.st_dev == original_dev
        assert linked_stat.st_ino == original_ino, f"{linked} is not a hard link to {original}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_config_manager.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
