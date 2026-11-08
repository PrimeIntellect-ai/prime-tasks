#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_apply_update.py
import ctypes
import errno
import hashlib
import io
import os
import pwd
import random
import shutil
import stat
import struct
import subprocess
import tarfile

PROJECT = "/home/user/project"
ARCHIVE = "/home/user/update.tar"
BINARY = "/tmp/apply_update_test"

IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
WATCH_MASK = IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def add_tar_file(tar, name, content):
    info = tarfile.TarInfo(name)
    info.size = len(content)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(content))


def chown_tree(path, uid, gid):
    os.chown(path, uid, gid)
    for root, dirs, files in os.walk(path):
        for name in dirs + files:
            os.chown(os.path.join(root, name), uid, gid)


def setup_state():
    token = "%016x" % random.getrandbits(64)
    random_name = "audit_" + token + ".dat"
    random_content = os.urandom(41)
    extra_parent_escape = "../audit_escape_" + token
    extra_contains_dotdot = "name.." + token
    extra_absolute = "/tmp/audit_absolute_" + token

    for path in [
        "/home/user/escaped.txt",
        "/etc/fake_root.txt",
        "/home/user/audit_escape_" + token,
        os.path.join(PROJECT, extra_contains_dotdot),
        extra_absolute,
    ]:
        try:
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
        except FileNotFoundError:
            pass

    shutil.rmtree(PROJECT, ignore_errors=True)
    os.makedirs(os.path.join(PROJECT, ".tmp"))
    os.makedirs(os.path.join(PROJECT, "src"))
    with open(os.path.join(PROJECT, "app.log"), "wb") as f:
        f.write(b"unchanged_content")
    with open(os.path.join(PROJECT, "config.json"), "wb") as f:
        f.write(b"v1_config")
    with open(os.path.join(PROJECT, "src/main.go"), "wb") as f:
        f.write(b"package main")

    try:
        os.unlink(ARCHIVE)
    except FileNotFoundError:
        pass
    with tarfile.open(ARCHIVE, "w") as tar:
        add_tar_file(tar, "app.log", b"unchanged_content")
        add_tar_file(tar, "config.json", b"v2_config")
        add_tar_file(tar, "feature.go", b"new_feature")
        add_tar_file(tar, random_name, random_content)
        add_tar_file(tar, "../escaped.txt", b"malicious_data")
        add_tar_file(tar, "/etc/fake_root.txt", b"malicious_data2")
        add_tar_file(tar, extra_parent_escape, b"escape")
        add_tar_file(tar, extra_contains_dotdot, b"contains-dotdot")
        add_tar_file(tar, extra_absolute, b"absolute")

    account = pwd.getpwnam("user")
    chown_tree(PROJECT, account.pw_uid, account.pw_gid)
    os.chown(ARCHIVE, account.pw_uid, account.pw_gid)
    os.chmod(PROJECT, 0o777)
    os.chmod(os.path.join(PROJECT, ".tmp"), 0o777)

    return {
        "token": token,
        "random_name": random_name,
        "random_content": random_content,
        "extra_parent_escape": extra_parent_escape,
        "extra_contains_dotdot": extra_contains_dotdot,
        "extra_absolute": extra_absolute,
    }


def start_inotify():
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, os.strerror(ctypes.get_errno())
    watches = {}
    for label, path in [("project", PROJECT), ("tmp", os.path.join(PROJECT, ".tmp"))]:
        wd = libc.inotify_add_watch(fd, path.encode(), WATCH_MASK)
        assert wd >= 0, os.strerror(ctypes.get_errno())
        watches[wd] = label
    return fd, watches


def read_inotify(fd, watches):
    events = []
    while True:
        try:
            data = os.read(fd, 65536)
        except OSError as exc:
            if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                break
            raise
        if not data:
            break
        offset = 0
        while offset < len(data):
            wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
            offset += 16
            raw_name = data[offset:offset + name_len]
            offset += name_len
            name = raw_name.split(b"\0", 1)[0].decode(errors="surrogateescape")
            events.append((watches.get(wd), mask, cookie, name))
    return events


def test_program_execution_and_final_state():
    dynamic = setup_state()
    app_path = os.path.join(PROJECT, "app.log")
    before = os.stat(app_path)

    fd, watches = start_inotify()
    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", BINARY],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            text=True,
        )
        events = read_inotify(fd, watches)
    finally:
        os.close(fd)

    assert result.returncode == 0, "Program failed:\nstdout:\n%s\nstderr:\n%s" % (result.stdout, result.stderr)

    # The checksum-identical archive entry must not alter the existing file or its metadata.
    after = os.stat(app_path)
    assert (after.st_ino, after.st_mtime_ns, after.st_ctime_ns, after.st_mode,
            after.st_uid, after.st_gid, after.st_size) == (
                before.st_ino, before.st_mtime_ns, before.st_ctime_ns,
                before.st_mode, before.st_uid, before.st_gid, before.st_size
            ), "app.log or its metadata was modified despite identical content"
    with open(app_path, "rb") as f:
        assert f.read() == b"unchanged_content"

    expected_files = {
        "app.log": b"unchanged_content",
        "config.json": b"v2_config",
        "feature.go": b"new_feature",
        dynamic["random_name"]: dynamic["random_content"],
        "src/main.go": b"package main",
    }
    for rel_path, content in expected_files.items():
        full_path = os.path.join(PROJECT, rel_path)
        assert os.path.isfile(full_path), "%s does not exist" % full_path
        with open(full_path, "rb") as f:
            assert f.read() == content, "%s has incorrect contents" % rel_path

    # Changed/new entries must arrive via renames from distinct files created in .tmp.
    created_tmp = {
        name for label, mask, cookie, name in events
        if label == "tmp" and (mask & IN_CREATE)
    }
    moved_from = {
        cookie: name for label, mask, cookie, name in events
        if label == "tmp" and (mask & IN_MOVED_FROM) and cookie
    }
    moved_to = {
        name: cookie for label, mask, cookie, name in events
        if label == "project" and (mask & IN_MOVED_TO) and cookie
    }
    changed_targets = {"config.json", "feature.go", dynamic["random_name"]}
    source_names = []
    for target in changed_targets:
        assert target in moved_to, "%s was not atomically renamed into place" % target
        cookie = moved_to[target]
        assert cookie in moved_from, "%s was not renamed from the .tmp directory" % target
        source_name = moved_from[cookie]
        assert source_name in created_tmp, "temporary source for %s was not created in .tmp" % target
        source_names.append(source_name)
    assert len(set(source_names)) == len(changed_targets), "Temporary file names were not unique"
    assert os.listdir(os.path.join(PROJECT, ".tmp")) == [], ".tmp contains leftover files"

    skipped_path = os.path.join(PROJECT, "skipped.txt")
    assert os.path.isfile(skipped_path), "%s does not exist" % skipped_path
    with open(skipped_path, "r") as f:
        skipped_lines = [line.strip() for line in f if line.strip()]
    expected_skipped = {
        "../escaped.txt",
        "/etc/fake_root.txt",
        dynamic["extra_parent_escape"],
        dynamic["extra_contains_dotdot"],
        dynamic["extra_absolute"],
    }
    assert set(skipped_lines) == expected_skipped
    assert len(skipped_lines) == len(expected_skipped)

    assert not os.path.exists("/home/user/escaped.txt")
    assert not os.path.exists(os.path.join(PROJECT, "escaped.txt"))
    assert not os.path.exists("/etc/fake_root.txt")
    assert not os.path.exists("/home/user/audit_escape_" + dynamic["token"])
    assert not os.path.exists(os.path.join(PROJECT, dynamic["extra_contains_dotdot"]))
    assert not os.path.exists(dynamic["extra_absolute"])

    manifest_path = os.path.join(PROJECT, "manifest.txt")
    assert os.path.isfile(manifest_path), "%s does not exist" % manifest_path
    expected_manifest_lines = [
        "%s %s" % (sha256(content), rel_path)
        for rel_path, content in expected_files.items()
    ]
    expected_manifest_lines.sort(key=lambda line: line.split(" ", 1)[1])
    with open(manifest_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_manifest_lines, (
        "Manifest contents/order do not match. Expected:\n%s\nGot:\n%s"
        % (expected_manifest_lines, actual_lines)
    )
TEST_EOF

if [ -f /home/user/apply_update.go ] && [ ! -L /home/user/apply_update.go ] \
   && go build -o /tmp/apply_update_test /home/user/apply_update.go \
   && python3 -m pytest /tmp/test_apply_update.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
