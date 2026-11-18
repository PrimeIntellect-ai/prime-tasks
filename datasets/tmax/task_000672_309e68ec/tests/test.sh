#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import select
import shutil
import stat
import struct
import subprocess
import time
import pytest

HOME = "/home/user"
ARCHIVE = os.path.join(HOME, "configs.pkg")
OUT = os.path.join(HOME, "extracted_configs")
SOURCE = os.path.join(HOME, "extractor.rs")
ARTIFACT = os.path.join(HOME, "extractor")
VERIFIER_BINARY = "/tmp/verifier_extractor"


def write_pkg(entries):
    with open(ARCHIVE, "wb") as f:
        f.write(bytes([len(entries)]))
        for path, payload in entries:
            path_bytes = path.encode("ascii")
            payload_bytes = payload.encode("utf-8")
            assert len(path_bytes) <= 255
            f.write(bytes([len(path_bytes)]))
            f.write(path_bytes)
            f.write(struct.pack("<I", len(payload_bytes)))
            f.write(payload_bytes)


def clean_output():
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT, exist_ok=True)


def run_extractor(binary):
    result = subprocess.run(
        [binary], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Extractor {binary} failed with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


# Validate both required deliverables and compile the submitted Rust source so its
# behavior, rather than only a pre-created output tree, is exercised.
assert os.path.isfile(SOURCE), f"Expected Rust source {SOURCE} was not found."
assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"{SOURCE} must be a regular file."
assert os.path.isfile(ARTIFACT), f"Expected compiled executable {ARTIFACT} was not found."
assert stat.S_ISREG(os.lstat(ARTIFACT).st_mode), f"{ARTIFACT} must be a regular file."
assert os.access(ARTIFACT, os.X_OK), f"{ARTIFACT} is not executable."
with open(ARTIFACT, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{ARTIFACT} is not a compiled native executable."

compile_result = subprocess.run(
    ["rustc", SOURCE, "-o", VERIFIER_BINARY],
    cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
)
assert compile_result.returncode == 0, (
    f"The submitted Rust source did not compile. stdout={compile_result.stdout!r}, "
    f"stderr={compile_result.stderr!r}"
)

# Recreate the specified archive, erase any agent-created outputs, and actually
# run the required /home/user/extractor before retaining the original checks.
write_pkg([
    ("app.csv", "env,production"),
    ("../pwned_sys.csv", "root,hello"),
    ("db/config.csv", "port,5432"),
])
clean_output()
for forbidden in [os.path.join(HOME, "pwned_sys.json"), os.path.join(HOME, "pwned_sys.csv")]:
    try:
        os.remove(forbidden)
    except FileNotFoundError:
        pass
run_extractor(ARTIFACT)


def test_app_json_extracted_correctly():
    path = "/home/user/extracted_configs/app.json"
    assert os.path.isfile(path), f"Expected file {path} was not found."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    assert data == {"env": "production"}, f"Content of {path} is incorrect. Got {data}"


def test_db_config_json_extracted_correctly():
    path = "/home/user/extracted_configs/db/config.json"
    assert os.path.isfile(path), f"Expected file {path} was not found."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    assert data == {"port": "5432"}, f"Content of {path} is incorrect. Got {data}"


def test_zip_slip_mitigated():
    forbidden_paths = [
        "/home/user/pwned_sys.json",
        "/home/user/pwned_sys.csv",
        "/home/user/extracted_configs/../pwned_sys.json",
        "/home/user/extracted_configs/../pwned_sys.csv"
    ]

    for path in forbidden_paths:
        normalized_path = os.path.normpath(path)
        assert not os.path.exists(normalized_path), f"Zip slip vulnerability detected: {normalized_path} should not exist."


def test_no_tmp_files_left():
    base_dir = "/home/user/extracted_configs"
    assert os.path.isdir(base_dir), f"Directory {base_dir} does not exist."

    tmp_files = []
    for root, dirs, files in os.walk(base_dir):
        for file in files:
            if file.endswith(".tmp"):
                tmp_files.append(os.path.join(root, file))

    assert not tmp_files, f"Temporary files were left behind: {tmp_files}"


def test_compiled_source_on_derived_inputs_and_traversals():
    token = secrets.token_hex(8)
    nested_name = f"service_{token}"
    plain_name = f"plain_{token}"
    escape_name = f"escape_{token}"
    absolute_name = f"absolute_{token}"
    key1 = f"key_{secrets.token_hex(4)}"
    value1 = f"value_{secrets.token_hex(8)}"
    key2 = f"other_{secrets.token_hex(4)}"
    value2 = f"setting_{secrets.token_hex(8)}"

    write_pkg([
        (f"services/{nested_name}.csv", f"{key1},{value1}\n{key2},{value2}"),
        (f"{plain_name}.csv", f"mode,{token}"),
        (f"nested/../../{escape_name}.csv", "bad,one"),
        (f"/home/user/{absolute_name}.csv", "bad,two"),
    ])
    clean_output()
    outside = [
        os.path.join(HOME, f"{escape_name}.json"),
        os.path.join(HOME, f"{absolute_name}.json"),
    ]
    for path in outside:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_extractor(VERIFIER_BINARY)

    with open(os.path.join(OUT, "services", nested_name + ".json"), "r") as f:
        assert json.load(f) == {key1: value1, key2: value2}
    with open(os.path.join(OUT, plain_name + ".json"), "r") as f:
        assert json.load(f) == {"mode": token}
    for path in outside:
        assert not os.path.exists(path), f"Traversal created forbidden path {path}"
    assert not any(name.endswith(".tmp") for _, _, files in os.walk(OUT) for name in files)


def test_atomic_temp_write_and_rename_are_observed():
    clean_output()
    target = os.path.join(OUT, "atomic.json")
    temp_target = target + ".tmp"
    sentinel = b"old configuration remains visible until rename"
    with open(target, "wb") as f:
        f.write(sentinel)

    value = "x" * (4 * 1024 * 1024)
    write_pkg([("atomic.csv", "blob," + value)])

    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_init1.restype = ctypes.c_int
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    inotify_add_watch.restype = ctypes.c_int

    IN_NONBLOCK = os.O_NONBLOCK
    IN_MODIFY = 0x00000002
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    IN_DELETE = 0x00000200
    mask = IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE

    fd = inotify_init1(IN_NONBLOCK)
    assert fd >= 0, "Could not initialize inotify for atomic-write verification"
    try:
        wd = inotify_add_watch(fd, OUT.encode(), mask)
        assert wd >= 0, "Could not watch extraction directory"

        proc = subprocess.Popen(
            [VERIFIER_BINARY], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True
        )
        stdout, stderr = proc.communicate(timeout=30)
        assert proc.returncode == 0, (
            f"Extractor failed during atomic-write test. stdout={stdout!r}, stderr={stderr!r}"
        )

        events = []
        while True:
            readable, _, _ = select.select([fd], [], [], 0.05)
            if not readable:
                break
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                break
            offset = 0
            while offset + 16 <= len(data):
                event_wd, event_mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode("utf-8", "replace")
                events.append((event_mask, cookie, name))
    finally:
        os.close(fd)

    assert any(mask & IN_CREATE and name == "atomic.json.tmp" for mask, _, name in events), \
        f"No creation of the required temporary file was observed: {events}"
    assert any(mask & IN_CLOSE_WRITE and name == "atomic.json.tmp" for mask, _, name in events), \
        f"The temporary file was not closed after writing: {events}"

    moved_from = {(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_FROM}
    moved_to = {(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_TO}
    matching_cookies = {
        cookie for cookie, name in moved_from
        if cookie and name == "atomic.json.tmp" and (cookie, "atomic.json") in moved_to
    }
    assert matching_cookies, f"No atomic rename from atomic.json.tmp to atomic.json was observed: {events}"

    assert not any(
        name == "atomic.json" and mask & (IN_MODIFY | IN_CLOSE_WRITE | IN_DELETE)
        for mask, _, name in events
    ), f"The final file was modified or removed non-atomically before replacement: {events}"
    assert not os.path.exists(temp_target), "Temporary file remained after atomic rename"
    with open(target, "r") as f:
        assert json.load(f) == {"blob": value}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
