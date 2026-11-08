#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess

import pytest

DIR_PATH = b"/home/user/legacy_archive"
SOURCE_PATH = "/home/user/normalize.cpp"
BINARY_PATH = "/home/user/normalize"
REBUILT_PATH = "/tmp/normalize_rebuilt"


def test_renamed_files_exist():
    """Test that the files have been renamed to UTF-8 with lowercase extensions."""
    expected_files = [
        b"caf\xc3\xa9.txt",
        b"m\xc3\xbcnchen.dat",
        b"r\xc3\xa9sum\xc3\xa9.doc",
        b"normal_file.csv"
    ]

    actual_files = os.listdir(DIR_PATH)

    for filename in expected_files:
        assert filename in actual_files, f"Expected file {filename!r} not found in {DIR_PATH!r}."


def test_old_files_removed():
    """Test that the old ISO-8859-1 files with uppercase extensions are gone."""
    old_files = [
        b"caf\xe9.TXT",
        b"m\xfcnchen.DAT",
        b"r\xe9sum\xe9.DOC",
        b"normal_file.CSV"
    ]

    actual_files = os.listdir(DIR_PATH)

    for filename in old_files:
        assert filename not in actual_files, f"Old file {filename!r} should have been renamed."


def test_log_file_contents():
    """Test that the normalization.log contains the correct mapping lines."""
    log_path = b"/home/user/normalization.log"
    assert os.path.isfile(log_path), "normalization.log does not exist."

    expected_lines = [
        b"/home/user/legacy_archive/caf\xe9.TXT -> /home/user/legacy_archive/caf\xc3\xa9.txt",
        b"/home/user/legacy_archive/m\xfcnchen.DAT -> /home/user/legacy_archive/m\xc3\xbcnchen.dat",
        b"/home/user/legacy_archive/r\xe9sum\xe9.DOC -> /home/user/legacy_archive/r\xc3\xa9sum\xc3\xa9.doc",
        b"/home/user/legacy_archive/normal_file.CSV -> /home/user/legacy_archive/normal_file.csv"
    ]

    with open(log_path, "rb") as f:
        content = f.read()

    for line in expected_lines:
        assert line in content, f"Expected log entry {line!r} not found in normalization.log."


def test_required_artifacts_exist_and_source_compiles():
    source_stat = os.lstat(SOURCE_PATH)
    binary_stat = os.lstat(BINARY_PATH)
    assert stat.S_ISREG(source_stat.st_mode), "normalize.cpp must be a regular file."
    assert stat.S_ISREG(binary_stat.st_mode), "normalize must be a regular file."
    assert os.access(BINARY_PATH, os.X_OK), "normalize is not executable."

    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-o", REBUILT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "normalize.cpp failed to compile:\n" + result.stderr.decode("utf-8", "replace")


def expected_name(old_name):
    if b"." in old_name:
        dot = old_name.rfind(b".")
        old_name = old_name[:dot + 1] + old_name[dot + 1:].lower()
    return old_name.decode("latin-1").encode("utf-8")


def clear_archive():
    os.makedirs(DIR_PATH, exist_ok=True)
    for entry in os.scandir(DIR_PATH):
        path = os.path.join(DIR_PATH, entry.name)
        if entry.is_dir(follow_symlinks=False):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def exercise(binary, marker):
    clear_archive()
    log_path = b"/home/user/normalization.log"
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass

    token = secrets.token_hex(8).encode("ascii")
    inputs = [
        b"caf\xe9_" + token + b".TXT",
        b"m\xfcnchen_" + token + b".DaT",
        b"multi_" + token + b".ARCHIVE.GZ",
        b"no_extension_" + token + b"_\xf1",
    ]
    payloads = {}
    for index, name in enumerate(inputs):
        payload = marker + b":" + str(index).encode("ascii")
        payloads[name] = payload
        with open(os.path.join(DIR_PATH, name), "wb") as f:
            f.write(payload)

    result = subprocess.run(
        [binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"{binary} failed:\n" + result.stderr.decode("utf-8", "replace")

    expected = {expected_name(name) for name in inputs}
    assert set(os.listdir(DIR_PATH)) == expected

    for old_name, payload in payloads.items():
        new_name = expected_name(old_name)
        with open(os.path.join(DIR_PATH, new_name), "rb") as f:
            assert f.read() == payload

    assert os.path.isfile(log_path), "normalization.log was not created."
    with open(log_path, "rb") as f:
        actual_lines = f.read().splitlines()

    expected_lines = {
        DIR_PATH + b"/" + old_name + b" -> " + DIR_PATH + b"/" + expected_name(old_name)
        for old_name in inputs
    }
    assert len(actual_lines) == len(inputs), "The log must contain one line per processed file."
    assert set(actual_lines) == expected_lines


def test_submitted_executable_handles_unseen_filenames():
    exercise(BINARY_PATH, b"submitted-binary")


def test_compiled_source_handles_unseen_filenames():
    exercise(REBUILT_PATH, b"rebuilt-source")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
