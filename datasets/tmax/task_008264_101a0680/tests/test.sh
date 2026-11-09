#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import struct
import tarfile

WORKSPACE_DIR = "/home/user/workspace"
RAW_DATA_DIR = os.path.join(WORKSPACE_DIR, "raw_data")
ORGANIZED_DIR = os.path.join(WORKSPACE_DIR, "organized")
ARCHIVE_PATH = os.path.join(WORKSPACE_DIR, "archive.tar.gz")
RULES_PATH = os.path.join(WORKSPACE_DIR, "rules.json")


def load_rules():
    with open(RULES_PATH, "r", encoding="utf-8") as f:
        rules = json.load(f)
    for key in ("datasets", "binaries", "logs"):
        assert isinstance(rules.get(key), list), f"rules.json has no valid {key} array"
    return rules


def elf_category(path):
    with open(path, "rb") as f:
        header = f.read(20)
    if len(header) < 20 or header[:4] != b"\x7fELF":
        return "other"
    data_encoding = header[5]
    if data_encoding == 1:
        machine = struct.unpack("<H", header[18:20])[0]
    elif data_encoding == 2:
        machine = struct.unpack(">H", header[18:20])[0]
    else:
        return "other"
    return "x86_64" if machine == 62 else "other"


def expected_csv(path):
    with open(path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert "status" in header, f"Missing status column in {path}"
        status_index = header.index("status")
        rows = [row for row in reader if row[status_index] != "ERROR"]
    return header, rows


def read_csv(path):
    with open(path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        return next(reader), list(reader)


def test_organized_directory_structure():
    assert os.path.isdir(ORGANIZED_DIR), f"Missing directory: {ORGANIZED_DIR}"
    assert os.path.isdir(os.path.join(ORGANIZED_DIR, "datasets")), "Missing datasets directory"
    assert os.path.isdir(os.path.join(ORGANIZED_DIR, "binaries", "x86_64")), "Missing binaries/x86_64 directory"
    assert os.path.isdir(os.path.join(ORGANIZED_DIR, "binaries", "other")), "Missing binaries/other directory"
    assert os.path.isdir(os.path.join(ORGANIZED_DIR, "logs")), "Missing logs directory"


def test_datasets_processed():
    data1_path = os.path.join(ORGANIZED_DIR, "datasets", "data1.csv")
    data2_path = os.path.join(ORGANIZED_DIR, "datasets", "data2.csv")

    assert os.path.isfile(data1_path), f"Missing file: {data1_path}"
    assert os.path.isfile(data2_path), f"Missing file: {data2_path}"

    def check_csv(filepath, expected_rows):
        with open(filepath, "r", newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            assert len(rows) == expected_rows, f"{filepath} has incorrect number of data rows."
            for row in rows:
                assert row.get("status") != "ERROR", f"Found ERROR row in {filepath}"

    check_csv(data1_path, 2)
    check_csv(data2_path, 2)


def test_all_dataset_values_match_sources():
    rules = load_rules()
    for name in rules["datasets"]:
        source = os.path.join(RAW_DATA_DIR, name)
        output = os.path.join(ORGANIZED_DIR, "datasets", name)
        assert os.path.isfile(output), f"Missing processed dataset: {output}"
        expected_header, expected_rows = expected_csv(source)
        actual_header, actual_rows = read_csv(output)
        assert actual_header == expected_header, f"Header changed in {output}"
        assert actual_rows == expected_rows, f"Filtered rows or field values are incorrect in {output}"


def test_binaries_hardlinked():
    worker_orig = os.path.join(RAW_DATA_DIR, "worker")
    worker_link = os.path.join(ORGANIZED_DIR, "binaries", "x86_64", "worker")
    dummy_orig = os.path.join(RAW_DATA_DIR, "dummy_arm")
    dummy_link = os.path.join(ORGANIZED_DIR, "binaries", "other", "dummy_arm")

    assert os.path.isfile(worker_link), f"Missing file: {worker_link}"
    assert os.path.isfile(dummy_link), f"Missing file: {dummy_link}"
    assert os.stat(worker_orig).st_ino == os.stat(worker_link).st_ino, "worker is not a hardlink to the original file"
    assert os.stat(dummy_orig).st_ino == os.stat(dummy_link).st_ino, "dummy_arm is not a hardlink to the original file"


def test_all_binaries_are_classified_and_hardlinked():
    rules = load_rules()
    for name in rules["binaries"]:
        source = os.path.join(RAW_DATA_DIR, name)
        category = elf_category(source)
        output = os.path.join(ORGANIZED_DIR, "binaries", category, name)
        assert os.path.isfile(output), f"Missing classified binary: {output}"
        source_stat = os.stat(source)
        output_stat = os.stat(output)
        assert (source_stat.st_dev, source_stat.st_ino) == (output_stat.st_dev, output_stat.st_ino), \
            f"{output} is not a hardlink to {source}"


def test_logs_symlinked():
    sys_orig = os.path.join(RAW_DATA_DIR, "sys.log")
    sys_link = os.path.join(ORGANIZED_DIR, "logs", "sys.log")
    debug_orig = os.path.join(RAW_DATA_DIR, "debug.log")
    debug_link = os.path.join(ORGANIZED_DIR, "logs", "debug.log")

    for link_path, orig_path in [(sys_link, sys_orig), (debug_link, debug_orig)]:
        assert os.path.islink(link_path), f"Not a symlink: {link_path}"
        target = os.readlink(link_path)
        abs_target = os.path.abspath(os.path.join(os.path.dirname(link_path), target))
        assert abs_target == orig_path, f"Symlink {link_path} does not point to {orig_path}"


def test_all_logs_symlinked():
    rules = load_rules()
    for name in rules["logs"]:
        source = os.path.join(RAW_DATA_DIR, name)
        output = os.path.join(ORGANIZED_DIR, "logs", name)
        assert os.path.islink(output), f"Not a symlink: {output}"
        resolved = os.path.abspath(os.path.join(os.path.dirname(output), os.readlink(output)))
        assert resolved == source, f"Symlink {output} does not point to {source}"


def test_archive_created_and_valid():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive missing: {ARCHIVE_PATH}"
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()
        paths = [m.name for m in members]
        assert any(p.endswith("datasets/data1.csv") for p in paths), "data1.csv missing from archive"
        assert any(p.endswith("binaries/x86_64/worker") for p in paths), "worker missing from archive"
        assert any(p.endswith("logs/sys.log") for p in paths), "sys.log missing from archive"
        sys_log_members = [m for m in members if m.name.endswith("logs/sys.log")]
        assert sys_log_members, "sys.log not found in tarball"
        assert sys_log_members[0].issym(), "sys.log is not a symlink in the tarball"


def test_archive_contains_complete_correct_organized_tree():
    rules = load_rules()
    assert os.path.isfile(ARCHIVE_PATH), f"Archive missing: {ARCHIVE_PATH}"

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()

        def normalized(member):
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            return name.rstrip("/")

        def locate(relative_suffix):
            suffix = relative_suffix.strip("/")
            matches = [m for m in members if normalized(m) == suffix or normalized(m).endswith("/" + suffix)]
            assert len(matches) == 1, f"Expected exactly one archive member ending in {suffix}, found {len(matches)}"
            return matches[0]

        for directory in ("organized", "organized/datasets", "organized/binaries",
                          "organized/binaries/x86_64", "organized/binaries/other", "organized/logs"):
            member = locate(directory)
            assert member.isdir(), f"Archive member {member.name} is not a directory"

        for name in rules["datasets"]:
            member = locate("organized/datasets/" + name)
            assert member.isfile(), f"Archived dataset {member.name} is not a regular file"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Cannot read archived dataset {member.name}"
            with io.TextIOWrapper(extracted, encoding="utf-8", newline="") as stream:
                reader = csv.reader(stream)
                actual_header = next(reader)
                actual_rows = list(reader)
            expected_header, expected_rows = expected_csv(os.path.join(RAW_DATA_DIR, name))
            assert actual_header == expected_header, f"Archived header changed for {name}"
            assert actual_rows == expected_rows, f"Archived rows or field values are incorrect for {name}"

        for name in rules["logs"]:
            member = locate("organized/logs/" + name)
            assert member.issym(), f"Archived log {member.name} is not a symlink"
            expected_source = os.path.join(RAW_DATA_DIR, name)
            filesystem_link = os.path.join(ORGANIZED_DIR, "logs", name)
            archived_target = os.path.abspath(os.path.join(os.path.dirname(filesystem_link), member.linkname))
            assert archived_target == expected_source, f"Archived symlink {member.name} has the wrong target"

        for name in rules["binaries"]:
            source = os.path.join(RAW_DATA_DIR, name)
            category = elf_category(source)
            member = locate(f"organized/binaries/{category}/{name}")
            assert member.islnk(), f"Archived binary {member.name} is not preserved as a hardlink"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Archived hardlink {member.name} has no readable target"
            archived_bytes = extracted.read()
            with open(source, "rb") as f:
                source_bytes = f.read()
            assert archived_bytes == source_bytes, f"Archived binary content differs for {name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
