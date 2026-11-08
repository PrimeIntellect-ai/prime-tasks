#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import stat
import tarfile
import zipfile

HOME = "/home/user"
SOURCE = "/home/user/project_backup.tar"
EXTRACTED = "/home/user/extracted"
OUTPUT = "/home/user/clean_logs.tar.gz"
SYSTEM_CHECK = "/home/user/system_check.txt"
KEY_RE = re.compile(rb"API_KEY: [A-Za-z0-9]+")


def source_members():
    assert os.path.isfile(SOURCE), f"Source archive {SOURCE} is missing."
    with tarfile.open(SOURCE, "r:*") as outer:
        regular = {m.name: outer.extractfile(m).read() for m in outer.getmembers() if m.isfile()}
    assert "logs/app.log" in regular, "Source archive no longer contains logs/app.log"
    assert "logs/nested.zip" in regular, "Source archive no longer contains logs/nested.zip"

    logs = {"app.log": regular["logs/app.log"]}
    with zipfile.ZipFile(io.BytesIO(regular["logs/nested.zip"]), "r") as nested:
        for info in nested.infolist():
            if info.is_dir():
                continue
            if info.filename.replace("\\", "/").split("/")[-1].endswith(".log"):
                basename = info.filename.replace("\\", "/").split("/")[-1]
                assert basename not in logs, f"Duplicate flattened log name in source: {basename}"
                logs[basename] = nested.read(info)
    return regular, {name: KEY_RE.sub(b"API_KEY: REDACTED", data) for name, data in logs.items()}


def test_system_check_untouched():
    path = SYSTEM_CHECK
    assert os.path.exists(path), f"File {path} is missing."
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f"File {path} is not a regular file."
    assert not os.path.islink(path), f"File {path} was replaced by a symlink."
    assert stat.S_IMODE(st.st_mode) == 0o777, f"File {path} metadata was modified."
    with open(path, "r") as f:
        content = f.read()
    assert content == "SAFE\n", f"File {path} was modified! Expected 'SAFE\\n', got {content!r}"


def test_no_home_writes_outside_extraction_and_required_output():
    allowed = {"project_backup.tar", "system_check.txt", "extracted", "clean_logs.tar.gz"}
    actual = set(os.listdir(HOME))
    unexpected = sorted(actual - allowed)
    assert not unexpected, f"Unexpected files were written outside {EXTRACTED}: {unexpected}"

    assert os.path.isdir(EXTRACTED), f"Extraction directory {EXTRACTED} is missing."
    assert not os.path.islink(EXTRACTED), f"Extraction directory {EXTRACTED} is a symlink."
    root = os.path.realpath(EXTRACTED)
    for dirpath, dirnames, filenames in os.walk(EXTRACTED, followlinks=False):
        for name in dirnames + filenames:
            path = os.path.join(dirpath, name)
            assert not os.path.islink(path), f"Unsafe symlink found in extraction tree: {path}"
            resolved = os.path.realpath(path)
            assert os.path.commonpath([root, resolved]) == root, f"Extracted path escapes extraction root: {path}"
            if os.path.isfile(path):
                assert os.lstat(path).st_nlink == 1, f"Unsafe hard-linked file found: {path}"


def test_extracted_source_and_logs():
    regular, expected_logs = source_members()

    app_path = os.path.join(EXTRACTED, "logs", "app.log")
    nested_path = os.path.join(EXTRACTED, "logs", "nested.zip")
    assert os.path.isfile(app_path), "The outer archive's logs/app.log was not extracted."
    assert os.path.isfile(nested_path), "The outer archive's logs/nested.zip was not extracted."
    with open(nested_path, "rb") as f:
        assert f.read() == regular["logs/nested.zip"], "The extracted nested archive was not preserved."

    found = {}
    for dirpath, _, filenames in os.walk(EXTRACTED, followlinks=False):
        for filename in filenames:
            if filename.endswith(".log"):
                path = os.path.join(dirpath, filename)
                assert filename not in found, f"Duplicate flattened log filename extracted: {filename}"
                with open(path, "rb") as f:
                    found[filename] = f.read()

    assert set(found) == set(expected_logs), f"Extracted logs differ from source logs: {sorted(found)}"
    for name, expected in expected_logs.items():
        assert found[name] == expected, f"Extracted {name} was fabricated, truncated, or incorrectly redacted."


def test_clean_logs_tar_exists():
    path = OUTPUT
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path) and not os.path.islink(path), f"File {path} is not a regular file."
    assert tarfile.is_tarfile(path), f"File {path} is not a valid tar archive."


def test_clean_logs_contents():
    path = OUTPUT
    assert os.path.exists(path), f"File {path} is missing."
    _, expected_logs = source_members()

    with tarfile.open(path, "r:gz") as tar:
        members = tar.getmembers()

        # Keep the original flattened-name assertion.
        names = [m.name for m in members if m.isfile()]
        assert sorted(names) == ["app.log", "db.log"], f"Expected 'app.log' and 'db.log' at the root of the archive, got {names}"

        assert len(members) == 2, f"Archive contains unexpected or unsafe members: {[m.name for m in members]}"
        assert all(m.isfile() for m in members), "Archive must contain only regular log files."
        assert len(names) == len(set(names)), "Archive contains duplicate member names."
        assert set(names) == set(expected_logs), f"Archive logs differ from logs derived from the source: {names}"
        for name in names:
            assert "/" not in name and "\\" not in name and name not in (".", ".."), f"Archive member is not flattened: {name}"
            content = tar.extractfile(tar.getmember(name)).read()
            assert content == expected_logs[name], f"{name} does not preserve the source content with only API keys redacted."

        # Keep the original per-file redaction assertions.
        app_log_content = tar.extractfile(tar.getmember("app.log")).read().decode("utf-8")
        assert "API_KEY: REDACTED" in app_log_content, "app.log does not contain 'API_KEY: REDACTED'"
        assert "aB39xZ" not in app_log_content, "app.log still contains the original API_KEY"

        db_log_content = tar.extractfile(tar.getmember("db.log")).read().decode("utf-8")
        assert "API_KEY: REDACTED" in db_log_content, "db.log does not contain 'API_KEY: REDACTED'"
        assert "99xYz1" not in db_log_content, "db.log still contains the original API_KEY"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
