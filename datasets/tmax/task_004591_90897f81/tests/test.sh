#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_workflow.py
import csv
import ctypes
import gzip
import hashlib
import os
import shutil
import stat
import struct
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

import pytest

ROOT = "/home/user/storage_dump"
SCRIPT = "/home/user/dedup_archives.sh"
CLEAN = "/home/user/clean_archives"
INDEX = "/home/user/archive_index"
REPORT = "/home/user/inventory_report.csv"
HEADER = ["Original_File_Name", "Mime_Type", "Status", "SHA256"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def read_report():
    assert os.path.isfile(REPORT), f"Report file {REPORT} is missing."
    with open(REPORT, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "Inventory report is empty."
    assert rows[0] == HEADER, f"Incorrect CSV header. Got: {rows[0]}"
    assert all(len(row) == 4 for row in rows[1:]), "Every CSV row must have four fields."
    names = [row[0] for row in rows[1:]]
    assert names == sorted(names), "CSV rows are not sorted alphabetically by Original_File_Name."
    return rows[1:]


def assert_original_state():
    expected_zip = sha256(f"{ROOT}/folder1/hidden_zip.txt")
    expected_tar = sha256(f"{ROOT}/folder2/backup.dat")
    rows = read_report()
    records = {row[0]: row for row in rows}
    for name in ["backup.dat", "backup_copy.dat", "bad.zip", "hidden_zip.txt", "readme.md"]:
        assert name in records, f"File {name} missing from inventory report."

    assert records["backup.dat"][2] == "Valid"
    assert records["backup.dat"][3] == expected_tar
    assert "tar" in records["backup.dat"][1]
    assert records["backup_copy.dat"][2] == "Valid"
    assert records["backup_copy.dat"][3] == expected_tar
    assert records["bad.zip"][2] == "Corrupt"
    assert records["bad.zip"][3] == "N/A"
    assert "zip" in records["bad.zip"][1]
    assert records["hidden_zip.txt"][2] == "Valid"
    assert records["hidden_zip.txt"][3] == expected_zip
    assert "zip" in records["hidden_zip.txt"][1]
    assert records["readme.md"][2] == "NotArchive"
    assert records["readme.md"][3] == "N/A"

    assert os.path.isdir(CLEAN)
    files = os.listdir(CLEAN)
    assert len(files) == 2, f"Expected exactly 2 files in {CLEAN}, got {len(files)}: {files}"
    zn = f"{expected_zip}.zip"
    tn = f"{expected_tar}.tar"
    assert zn in files and tn in files
    assert os.stat(f"{ROOT}/folder1/hidden_zip.txt").st_ino == os.stat(f"{CLEAN}/{zn}").st_ino
    assert os.stat(f"{ROOT}/folder2/backup.dat").st_ino == os.stat(f"{CLEAN}/{tn}").st_ino

    assert os.path.isdir(INDEX)
    links = {
        f"{INDEX}/zip/hidden_zip.txt": f"{CLEAN}/{zn}",
        f"{INDEX}/tar/backup.dat": f"{CLEAN}/{tn}",
        f"{INDEX}/tar/backup_copy.dat": f"{CLEAN}/{tn}",
    }
    for link, target in links.items():
        assert os.path.islink(link), f"{link} is missing or not a symlink."
        assert os.readlink(link) == target, f"Symlink {link} points to the wrong target."


def true_mime(path):
    return subprocess.check_output(
        ["file", "--brief", "--mime-type", path], text=True
    ).strip()


def integrity_ok(path, mime):
    commands = {
        "application/zip": ["unzip", "-tqq", path],
        "application/gzip": ["gzip", "-t", path],
        "application/x-tar": ["tar", "-tf", path],
    }
    if mime not in commands:
        return None
    return subprocess.run(
        commands[mime], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    ).returncode == 0


def expected_records():
    result = {}
    sources = {}
    for base, _, files in os.walk(ROOT):
        for name in files:
            path = os.path.join(base, name)
            assert name not in result, "Verifier fixtures require unique basenames."
            mime = true_mime(path)
            ok = integrity_ok(path, mime)
            if ok is None:
                status, digest = "NotArchive", "N/A"
            elif ok:
                status, digest = "Valid", sha256(path)
            else:
                status, digest = "Corrupt", "N/A"
            result[name] = [name, mime, status, digest]
            sources[name] = path
    return result, sources


def run_with_atomic_watch():
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK)
    assert fd >= 0, "Could not initialize inotify."
    mask = 0x00000008 | 0x00000080 | 0x00000100  # CLOSE_WRITE, MOVED_TO, CREATE
    wd = libc.inotify_add_watch(fd, b"/home/user", mask)
    assert wd >= 0, "Could not watch report directory."
    try:
        proc = subprocess.run(
            ["/bin/bash", SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=60
        )
        assert proc.returncode == 0, f"Script failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
        data = b""
        while True:
            try:
                part = os.read(fd, 65536)
                if not part:
                    break
                data += part
            except BlockingIOError:
                break
    finally:
        os.close(fd)

    events = []
    offset = 0
    while offset + 16 <= len(data):
        _, event_mask, _, length = struct.unpack_from("iIII", data, offset)
        raw_name = data[offset + 16:offset + 16 + length]
        name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
        events.append((event_mask, name))
        offset += 16 + length

    report_events = [m for m, n in events if n == "inventory_report.csv"]
    assert any(m & 0x00000080 for m in report_events), \
        "inventory_report.csv was not installed by an atomic rename/move."
    assert not any(m & 0x00000100 for m in report_events), \
        "inventory_report.csv was created and written directly instead of atomically moved."


@pytest.fixture(scope="module")
def workflow():
    st = os.lstat(SCRIPT)
    assert stat.S_ISREG(st.st_mode), f"{SCRIPT} must be a regular Bash script."
    assert st.st_size > 0, f"{SCRIPT} is empty."

    # Preserve and execute all checks made against the original fixtures.
    assert_original_state()

    token = uuid.uuid4().hex[:12]
    nested = os.path.join(ROOT, f"generated-{token}", "deep folder", "more")
    os.makedirs(nested)
    payload = os.path.join(nested, f"payload {token}.txt")
    with open(payload, "wb") as f:
        f.write(os.urandom(257) + b" dynamic archive payload\n")

    zip_name = f"quarterly archive {token}.misnamed"
    zip_path = os.path.join(nested, zip_name)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(payload, arcname="inside file.txt")

    gz_name = f"compressed stream {token}.data"
    gz_path = os.path.join(nested, gz_name)
    with open(payload, "rb") as src, gzip.open(gz_path, "wb") as dst:
        shutil.copyfileobj(src, dst)
    gz_copy_name = f"duplicate stream {token}.odd"
    gz_copy_path = os.path.join(nested, gz_copy_name)
    shutil.copyfile(gz_path, gz_copy_path)

    corrupt_name = f"damaged stream {token}.blob"
    corrupt_path = os.path.join(nested, corrupt_name)
    with open(corrupt_path, "wb") as f:
        f.write(b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03not-a-valid-deflate-stream")

    plain_name = f"notes with spaces {token}.bin"
    with open(os.path.join(nested, plain_name), "w") as f:
        f.write("ordinary text, not an archive\n")

    # The payload was only used to construct archives; leave a dynamic ordinary file.
    assert true_mime(zip_path) == "application/zip"
    assert true_mime(gz_path) == "application/gzip"
    assert true_mime(corrupt_path) == "application/gzip"
    assert not integrity_ok(corrupt_path, "application/gzip")

    shutil.rmtree(CLEAN, ignore_errors=True)
    shutil.rmtree(INDEX, ignore_errors=True)
    try:
        os.unlink(REPORT)
    except FileNotFoundError:
        pass

    run_with_atomic_watch()
    expected, sources = expected_records()
    return expected, sources, {
        "zip": zip_name, "gzip": gz_name, "gzip_copy": gz_copy_name,
        "corrupt": corrupt_name, "plain": plain_name
    }


def test_dynamic_recursive_processing(workflow):
    expected, sources, generated = workflow
    rows = read_report()
    assert len(rows) == len(expected), "Report must contain exactly one row for every recursively discovered file."
    actual = {row[0]: row for row in rows}
    assert len(actual) == len(rows), "Report contains duplicate basenames."
    assert actual == expected

    assert actual[generated["zip"]][2] == "Valid"
    assert actual[generated["gzip"]][2] == "Valid"
    assert actual[generated["gzip_copy"]][2] == "Valid"
    assert actual[generated["corrupt"]][2:] == ["Corrupt", "N/A"]
    assert actual[generated["plain"]][2:] == ["NotArchive", "N/A"]


def test_dynamic_clean_archives_are_deduplicated_hard_links(workflow):
    expected, sources, _ = workflow
    valid = {name: row for name, row in expected.items() if row[2] == "Valid"}
    ext = {"application/zip": "zip", "application/gzip": "gz", "application/x-tar": "tar"}
    expected_names = {f"{row[3]}.{ext[row[1]]}" for row in valid.values()}
    assert os.path.isdir(CLEAN)
    assert set(os.listdir(CLEAN)) == expected_names

    for clean_name in expected_names:
        clean_path = os.path.join(CLEAN, clean_name)
        assert stat.S_ISREG(os.lstat(clean_path).st_mode)
        digest = clean_name.split(".", 1)[0]
        candidates = [sources[n] for n, row in valid.items() if row[3] == digest]
        assert any(os.path.samefile(clean_path, source) for source in candidates), \
            f"{clean_path} is not a hard link to a matching source archive."


def test_dynamic_index_symlinks(workflow):
    expected, _, _ = workflow
    ext = {"application/zip": "zip", "application/gzip": "gz", "application/x-tar": "tar"}
    assert os.path.isdir(INDEX)
    for name, row in expected.items():
        if row[2] != "Valid":
            continue
        target = os.path.join(CLEAN, f"{row[3]}.{ext[row[1]]}")
        link = os.path.join(INDEX, ext[row[1]], name)
        assert os.path.islink(link), f"{link} is missing or not a symbolic link."
        assert os.readlink(link) == target, f"{link} points to the wrong clean archive."
PY

if python3 -m pytest /tmp/test_workflow.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
