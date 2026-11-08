#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib

EXTRACTED_DIR = "/home/user/extracted"
MANIFEST_PATH = "/home/user/manifest.txt"
VULN_TARGET_PATH = "/home/user/secret.txt"

def test_zip_slip_mitigated():
    assert not os.path.exists(VULN_TARGET_PATH), (
        f"Zip slip vulnerability was exploited! Found file at {VULN_TARGET_PATH}"
    )

def test_secret_txt_extracted_safely():
    safe_path = os.path.join(EXTRACTED_DIR, "secret.txt")
    assert os.path.exists(safe_path), f"Expected extracted file not found at {safe_path}"
    with open(safe_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert content == "秘密のデータ", f"Content of {safe_path} is incorrect."

def test_records_csv_extracted():
    path1 = os.path.join(EXTRACTED_DIR, "valid_data", "records.csv")
    path2 = os.path.join(EXTRACTED_DIR, "records.csv")
    actual_path = None
    if os.path.exists(path1):
        actual_path = path1
    elif os.path.exists(path2):
        actual_path = path2
    assert actual_path is not None, f"records.csv not found in {EXTRACTED_DIR} or {os.path.join(EXTRACTED_DIR, 'valid_data')}"
    with open(actual_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert content == "名前,年齢", f"Content of {actual_path} is incorrect."

def test_no_tmp_files_left_behind():
    for root, _, files in os.walk(EXTRACTED_DIR):
        for file in files:
            assert not file.endswith(".tmp"), f"Temporary file left behind: {os.path.join(root, file)}"

def test_manifest_exists_and_correct():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file not found at {MANIFEST_PATH}"
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 2, f"Manifest should contain exactly 2 lines, found {len(lines)}"
    records_hash = hashlib.sha256("名前,年齢".encode("utf-8")).hexdigest()
    secret_hash = hashlib.sha256("秘密のデータ".encode("utf-8")).hexdigest()
    expected_line1 = f"{records_hash}  records.csv"
    expected_line2 = f"{secret_hash}  secret.txt"
    assert lines[0] == expected_line1, f"Manifest line 1 incorrect. Expected '{expected_line1}', got '{lines[0]}'"
    assert lines[1] == expected_line2, f"Manifest line 2 incorrect. Expected '{expected_line2}', got '{lines[1]}'"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_extractor_behavior.py
import base64
import ctypes
import hashlib
import os
import secrets
import shutil
import struct
import subprocess
import sys
import zlib

HOME = "/home/user"
ARCHIVE = os.path.join(HOME, "dataset.carch")
OUT = os.path.join(HOME, "extracted")
MANIFEST = os.path.join(HOME, "manifest.txt")


def find_scripts():
    found = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if os.path.join(root, d) != OUT and not d.startswith(".")]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".py") and os.path.isfile(path) and not os.path.islink(path):
                found.append(path)
    return sorted(found)


def make_case():
    token = secrets.token_hex(12)
    entries = [
        (f"../escaped_{token}.txt", "shift_jis", f"秘密のデータ-{token}"),
        (f"../../beta_{token}.csv", "euc_jp", f"名前,年齢\n太郎,42\n{token}"),
        (f"gamma_{token}.txt", "utf-8", f"dynamic UTF-8 payload {token} 雪"),
    ]
    blocks = []
    expected = {}
    escaped = []
    for archive_name, encoding, text in entries:
        raw = text.encode(encoding)
        packed = base64.b64encode(zlib.compress(raw)).decode("ascii")
        blocks.extend([
            f"FILE: {archive_name}",
            f"SIZE: {len(raw)}",
            f"ENCODING: {encoding}",
            f"DATA: {packed}",
        ])
        basename = os.path.basename(archive_name)
        expected[basename] = text
        if ".." in archive_name.split("/"):
            escaped.append(os.path.normpath(os.path.join(OUT, archive_name)))
    return "\n".join(blocks) + "\n", expected, escaped


def prepare(archive_text, escaped):
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT, exist_ok=True)
    try:
        os.unlink(MANIFEST)
    except FileNotFoundError:
        pass
    for path in escaped:
        if not path.startswith(OUT + os.sep):
            try:
                if os.path.isdir(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
            except FileNotFoundError:
                pass
    with open(ARCHIVE, "w", encoding="utf-8", newline="\n") as f:
        f.write(archive_text)


def open_inotify():
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    if fd < 0:
        raise OSError(ctypes.get_errno(), "inotify_init1 failed")
    IN_MOVED_TO = 0x00000080
    wd = libc.inotify_add_watch(fd, OUT.encode(), IN_MOVED_TO)
    if wd < 0:
        err = ctypes.get_errno()
        os.close(fd)
        raise OSError(err, "inotify_add_watch failed")
    return fd


def moved_destinations(fd):
    names = []
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        offset = 0
        while offset + 16 <= len(data):
            _, mask, _, length = struct.unpack_from("iIII", data, offset)
            offset += 16
            raw_name = data[offset:offset + length]
            offset += length
            name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
            if mask & 0x00000080:
                names.append(name)
    return names


def validate(expected, escaped, moved):
    expected_names = sorted(expected)
    actual_names = []
    for root, _, files in os.walk(OUT):
        for name in files:
            rel = os.path.relpath(os.path.join(root, name), OUT)
            actual_names.append(rel)
            if name.endswith(".tmp"):
                raise AssertionError(f"temporary file left behind: {rel}")
    if sorted(actual_names) != expected_names:
        raise AssertionError(f"unexpected extracted files: {sorted(actual_names)}")

    for name, text in expected.items():
        path = os.path.join(OUT, name)
        with open(path, "r", encoding="utf-8") as f:
            if f.read() != text:
                raise AssertionError(f"incorrect dynamically generated content in {name}")
        if name not in moved:
            raise AssertionError(f"{name} was not atomically renamed into place")

    for path in escaped:
        if not path.startswith(OUT + os.sep) and os.path.exists(path):
            raise AssertionError(f"path traversal created {path}")

    with open(MANIFEST, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f if line.strip()]
    wanted = [
        f"{hashlib.sha256(expected[name].encode('utf-8')).hexdigest()}  {name}"
        for name in expected_names
    ]
    if lines != wanted:
        raise AssertionError(f"dynamic manifest incorrect: {lines!r}")


def main():
    scripts = find_scripts()
    if not scripts:
        raise AssertionError("no Python extraction script found under /home/user")

    archive_text, expected, escaped = make_case()
    failures = []
    for script in scripts:
        prepare(archive_text, escaped)
        fd = open_inotify()
        try:
            result = subprocess.run(
                [sys.executable, script], cwd=HOME,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=20
            )
            moved = moved_destinations(fd)
        except Exception as exc:
            failures.append(f"{script}: {exc}")
            continue
        finally:
            os.close(fd)

        if result.returncode != 0:
            failures.append(f"{script}: exited {result.returncode}: {result.stderr[-500:]}")
            continue
        try:
            validate(expected, escaped, moved)
            return
        except Exception as exc:
            failures.append(f"{script}: {exc}")

    raise AssertionError("no discovered Python script passed dynamic extraction tests:\n" + "\n".join(failures))


if __name__ == "__main__":
    main()
DYNAMIC_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 \
   && python3 /tmp/test_extractor_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
