#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import json
import os
import shutil
import stat
import struct
import subprocess
import time
import uuid

DUMP_DIR = "/home/user/project_dump"
ORG_DIR = "/home/user/organized_assets"
INDEX_FILE = os.path.join(ORG_DIR, "index.json")

EXPECTED = [
    {"file": "asset_01.bin", "type": "image", "hardlinks": 2},
    {"file": "asset_03.bin", "type": "image", "hardlinks": 1},
    {"file": "data_01.dat", "type": "custom", "hardlinks": 2},
    {"file": "data_02.dat", "type": "custom", "hardlinks": 1},
    {"file": "sys_01.log", "type": "log", "hardlinks": 2},
    {"file": "sys_02.log", "type": "log", "hardlinks": 1},
]

PAIRS = [
    ("asset_01.bin", "asset_02.bin"),
    ("data_01.dat", "data_03.dat"),
    ("sys_01.log", "sys_03.log"),
]


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.digest()


def test_original_contents_and_headers_preserved():
    expected_layout = {
        "asset_01.bin": (10 * 1024 * 1024 + 8, b"\x89PNG\x00\x01\x02\x03"),
        "asset_02.bin": (10 * 1024 * 1024 + 8, b"\x89PNG\x00\x01\x02\x03"),
        "asset_03.bin": (5 * 1024 * 1024 + 8, b"\x89PNG\x04\x05\x06\x07"),
        "data_01.dat": (2 * 1024 * 1024 + 8, b"\xDA\x7A\xBE\xEF\xAA\xBB\xCC\xDD"),
        "data_03.dat": (2 * 1024 * 1024 + 8, b"\xDA\x7A\xBE\xEF\xAA\xBB\xCC\xDD"),
        "data_02.dat": (1 * 1024 * 1024 + 8, b"\xDA\x7A\xBE\xEF\x11\x22\x33\x44"),
        "sys_01.log": (36, b"ERR Connection timeout on port 8080\n"),
        "sys_03.log": (36, b"ERR Connection timeout on port 8080\n"),
        "sys_02.log": (32, b"ERR Disk space low on /dev/sda1\n"),
    }
    assert set(os.listdir(DUMP_DIR)) == set(expected_layout)
    for name, (size, prefix) in expected_layout.items():
        path = os.path.join(DUMP_DIR, name)
        assert os.path.isfile(path) and not os.path.islink(path), f"Missing regular file: {path}"
        assert os.path.getsize(path) == size, f"Original size was not preserved for {name}"
        with open(path, "rb") as f:
            assert f.read(len(prefix)) == prefix, f"Original header/content was not preserved for {name}"

    for base, duplicate in PAIRS:
        assert digest(os.path.join(DUMP_DIR, base)) == digest(os.path.join(DUMP_DIR, duplicate))

    unique = ["asset_01.bin", "asset_03.bin", "data_01.dat", "data_02.dat", "sys_01.log", "sys_02.log"]
    hashes = [digest(os.path.join(DUMP_DIR, name)) for name in unique]
    assert len(set(hashes)) == len(hashes), "Distinct original files were incorrectly merged"


def test_hardlinks_created():
    for base, dup in PAIRS:
        base_path = os.path.join(DUMP_DIR, base)
        dup_path = os.path.join(DUMP_DIR, dup)
        assert os.path.exists(base_path), f"Base file missing: {base_path}"
        assert os.path.exists(dup_path), f"Duplicate file missing: {dup_path}"
        base_stat = os.stat(base_path)
        dup_stat = os.stat(dup_path)
        assert (base_stat.st_dev, base_stat.st_ino) == (dup_stat.st_dev, dup_stat.st_ino), (
            f"Files {base} and {dup} should be hardlinked"
        )


def test_symlink_organization():
    expected_symlinks = [
        ("image", "asset_01.bin"),
        ("image", "asset_03.bin"),
        ("custom", "data_01.dat"),
        ("custom", "data_02.dat"),
        ("log", "sys_01.log"),
        ("log", "sys_02.log"),
    ]
    for category, filename in expected_symlinks:
        symlink_path = os.path.join(ORG_DIR, category, filename)
        target_path = os.path.join(DUMP_DIR, filename)
        assert os.path.islink(symlink_path), f"Expected symlink at {symlink_path}"
        actual_target = os.readlink(symlink_path)
        resolved_target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), actual_target))
        assert resolved_target == target_path, f"{symlink_path} points to {actual_target}, not {target_path}"


def test_index_json_content():
    assert os.path.exists(INDEX_FILE), f"Index file missing: {INDEX_FILE}"
    with open(INDEX_FILE, "r") as f:
        data = json.load(f)
    assert data == EXPECTED


def find_scripts():
    candidates = []
    excluded = {os.path.realpath(DUMP_DIR), os.path.realpath(ORG_DIR)}
    for root in ("/home/user", "/tmp"):
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            real_current = os.path.realpath(current)
            dirs[:] = [d for d in dirs if os.path.realpath(os.path.join(current, d)) not in excluded and d not in {".cache", "__pycache__"}]
            if any(real_current == p or real_current.startswith(p + os.sep) for p in excluded):
                continue
            for name in files:
                path = os.path.join(current, name)
                if path == "/tmp/test_final_state.py" or path.startswith("/tmp/pytest-"):
                    continue
                try:
                    st = os.stat(path)
                    if not stat.S_ISREG(st.st_mode) or st.st_size > 2 * 1024 * 1024:
                        continue
                    with open(path, "rb") as f:
                        first = f.read(256)
                except OSError:
                    continue
                if name.endswith((".py", ".sh", ".bash", ".pl", ".rb")) or first.startswith(b"#!"):
                    candidates.append(path)
    return sorted(set(candidates))


def command_for(path):
    if path.endswith(".py"):
        return ["python3", path]
    if path.endswith((".sh", ".bash")):
        return ["bash", path]
    return [path]


def write_fixture():
    os.makedirs(DUMP_DIR, exist_ok=True)
    payloads = {
        "z_image.bin": b"\x89PNG" + os.urandom(131077),
        "middle_image.bin": b"\x89PNG" + os.urandom(65539),
        "x_custom.dat": b"\xDA\x7A\xBE\xEF" + os.urandom(32771),
        "only_custom.dat": b"\xDA\x7A\xBE\xEF" + os.urandom(16387),
        "z_log.log": b"ERR generated test log\n",
        "only_log.log": b"ERR another generated log\n",
    }
    payloads["a_image.bin"] = payloads["z_image.bin"]
    payloads["b_custom.dat"] = payloads["x_custom.dat"]
    payloads["a_log.log"] = payloads["z_log.log"]
    for name, content in payloads.items():
        with open(os.path.join(DUMP_DIR, name), "wb") as f:
            f.write(content)
    return payloads


def read_move_events(fd):
    names = []
    time.sleep(0.05)
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset + 16 <= len(data):
            _, mask, _, length = struct.unpack_from("iIII", data, offset)
            raw_name = data[offset + 16:offset + 16 + length]
            name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
            if mask & 0x80:
                names.append(name)
            offset += 16 + length
    return names


def validate_generated(payloads):
    groups = [
        ("a_image.bin", "z_image.bin"),
        ("b_custom.dat", "x_custom.dat"),
        ("a_log.log", "z_log.log"),
    ]
    for base, dup in groups:
        a, b = os.stat(os.path.join(DUMP_DIR, base)), os.stat(os.path.join(DUMP_DIR, dup))
        assert (a.st_dev, a.st_ino) == (b.st_dev, b.st_ino)
    for name, content in payloads.items():
        with open(os.path.join(DUMP_DIR, name), "rb") as f:
            assert f.read() == content, f"Script changed the content of {name}"

    expected = [
        {"file": "a_image.bin", "type": "image", "hardlinks": 2},
        {"file": "a_log.log", "type": "log", "hardlinks": 2},
        {"file": "b_custom.dat", "type": "custom", "hardlinks": 2},
        {"file": "middle_image.bin", "type": "image", "hardlinks": 1},
        {"file": "only_custom.dat", "type": "custom", "hardlinks": 1},
        {"file": "only_log.log", "type": "log", "hardlinks": 1},
    ]
    with open(INDEX_FILE) as f:
        assert json.load(f) == expected
    for item in expected:
        link = os.path.join(ORG_DIR, item["type"], item["file"])
        assert os.path.islink(link)
        assert os.path.realpath(link) == os.path.join(DUMP_DIR, item["file"])


def test_script_exists_runs_generically_and_atomically():
    candidates = find_scripts()
    assert candidates, "No automation script was found under /home/user or /tmp"

    token = uuid.uuid4().hex
    saved_dump = f"/home/.verifier_dump_{token}"
    saved_org = f"/home/.verifier_org_{token}"
    os.rename(DUMP_DIR, saved_dump)
    os.rename(ORG_DIR, saved_org)
    errors = []
    passed = False
    try:
        for script in candidates:
            shutil.rmtree(DUMP_DIR, ignore_errors=True)
            shutil.rmtree(ORG_DIR, ignore_errors=True)
            payloads = write_fixture()
            os.makedirs(ORG_DIR, exist_ok=True)

            libc = ctypes.CDLL(None, use_errno=True)
            fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
            if fd < 0:
                raise OSError(ctypes.get_errno(), "inotify_init1 failed")
            wd = libc.inotify_add_watch(fd, ORG_DIR.encode(), 0x80)
            if wd < 0:
                os.close(fd)
                raise OSError(ctypes.get_errno(), "inotify_add_watch failed")
            try:
                result = subprocess.run(
                    command_for(script), cwd=os.path.dirname(script) or "/",
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    timeout=30, text=True
                )
                moved_names = read_move_events(fd)
                if result.returncode != 0:
                    raise AssertionError(f"exit {result.returncode}: {result.stdout[-1000:]}")
                validate_generated(payloads)
                assert "index.json" in moved_names, "index.json was not installed by an atomic rename"
                passed = True
                break
            except Exception as exc:
                errors.append(f"{script}: {exc}")
            finally:
                os.close(fd)
    finally:
        shutil.rmtree(DUMP_DIR, ignore_errors=True)
        shutil.rmtree(ORG_DIR, ignore_errors=True)
        os.rename(saved_dump, DUMP_DIR)
        os.rename(saved_org, ORG_DIR)

    assert passed, "No submitted script passed a generated-input and atomic-write test:\n" + "\n".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
