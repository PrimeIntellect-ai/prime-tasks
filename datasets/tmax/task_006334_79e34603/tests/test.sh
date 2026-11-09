#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tarfile

EXPECTED = {
    "error_1.log": '''[2023-10-01 10:10:22] ERROR: Disk Space Critical
Module: StorageController
Traceback (most recent call last):
  File "storage.py", line 42, in check_space
    raise DiskFullException()
SESSION_TOKEN=REDACTED
''',
    "error_2.log": '''[2023-10-01 10:15:30] ERROR: Disk Space Critical
Module: LogWriter
Details: Failed to write to /var/log/app.log
SESSION_TOKEN=REDACTED
Please free up space immediately.
''',
    "error_3.log": '''[2023-10-01 10:20:00] ERROR: Disk Space Critical
Module: DatabaseSync
SESSION_TOKEN=REDACTED
Sync failed due to ENOSPC.
''',
}


def test_extractor_cpp_exists():
    assert os.path.isfile("/home/user/extractor.cpp"), "C++ source file /home/user/extractor.cpp is missing."
    assert os.path.isfile("/home/user/system.log"), "Original /home/user/system.log is missing."


def test_extractor_executable_exists():
    assert os.path.isfile("/home/user/extractor"), "Executable /home/user/extractor is missing."
    assert os.access("/home/user/extractor", os.X_OK), "/home/user/extractor is not executable."


def test_disk_errors_directory():
    assert os.path.isdir("/home/user/disk_errors"), "Directory /home/user/disk_errors is missing."
    files = sorted(os.listdir("/home/user/disk_errors"))
    expected_files = ["error_1.log", "error_2.log", "error_3.log"]
    assert files == expected_files, f"Expected files {expected_files} in /home/user/disk_errors, but got {files}."


def test_error_1_content():
    with open("/home/user/disk_errors/error_1.log", "r") as f:
        content = f.read()
    assert content.strip() == EXPECTED["error_1.log"].strip(), "Content of error_1.log does not match expected redacted output."


def test_error_2_content():
    with open("/home/user/disk_errors/error_2.log", "r") as f:
        content = f.read()
    assert content.strip() == EXPECTED["error_2.log"].strip(), "Content of error_2.log does not match expected redacted output."


def test_error_3_content():
    with open("/home/user/disk_errors/error_3.log", "r") as f:
        content = f.read()
    assert content.strip() == EXPECTED["error_3.log"].strip(), "Content of error_3.log does not match expected redacted output."


def test_backup_archive_exists_and_valid():
    archive_path = "/home/user/errors_backup.tar.gz"
    assert os.path.isfile(archive_path), f"Backup archive {archive_path} is missing."
    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            members = [m for m in tar.getmembers() if m.isfile()]
            relevant = [m for m in members if os.path.basename(m.name) in EXPECTED]
            basenames = [os.path.basename(m.name) for m in relevant]
            assert sorted(basenames) == sorted(EXPECTED), "Tarball does not contain exactly one copy of each expected log file."
            assert sorted(os.path.basename(m.name) for m in members) == sorted(EXPECTED), "Tarball contains unexpected regular files."
            for member in relevant:
                name = os.path.basename(member.name)
                archived = tar.extractfile(member)
                assert archived is not None, f"Could not read {name} from tarball."
                content = archived.read().decode("utf-8")
                assert content.strip() == EXPECTED[name].strip(), f"Archived content of {name} is incorrect."
    except tarfile.ReadError:
        assert False, f"File {archive_path} is not a valid gzip-compressed tarball."


def make_dynamic_fixture():
    nonce = secrets.token_hex(8)
    tokens = [secrets.token_hex(7), secrets.token_hex(9).upper(), "AbC" + secrets.token_hex(5)]
    lines = [
        f"[2041-07-01 00:00:00] INFO: unrelated {nonce}",
        "SESSION_TOKEN=OutsideBlock123",
        f"[2041-07-01 00:00:01] ERROR: Disk Space Critical id={nonce}-one",
        f"Module: Dynamic-{nonce}",
        f"SESSION_TOKEN={tokens[0]} and SESSION_TOKEN={tokens[1]}!",
        "  [this indented bracket is still part of the event]",
        "[2041-07-01 00:00:02] INFO: boundary",
        "continuation that must not be extracted",
        "[2041-07-01 00:00:03] ERROR: A different failure",
        "SESSION_TOKEN=DoNotExtract999",
        f"[2041-07-01 00:00:04] NOTICE: text before ERROR: Disk Space Critical marker={nonce}",
        "A matching event may contain the required exact string anywhere on its first line.",
        f"prefix SESSION_TOKEN={tokens[2]} suffix",
        "[2041-07-01 00:00:05] WARN: next event",
        f"[2041-07-01 00:00:06] ERROR: Disk Space Critical final={nonce}",
        "No token in this block.",
        f"Unique payload {nonce}",
    ]
    text = "\n".join(lines) + "\n"

    expected = []
    current = None
    for line in text.splitlines():
        if line.startswith("["):
            if current is not None:
                expected.append("\n".join(current) + "\n")
                current = None
            if "ERROR: Disk Space Critical" in line:
                current = [re.sub(r"SESSION_TOKEN=[a-zA-Z0-9]+", "SESSION_TOKEN=REDACTED", line)]
        elif current is not None:
            current.append(re.sub(r"SESSION_TOKEN=[a-zA-Z0-9]+", "SESSION_TOKEN=REDACTED", line))
    if current is not None:
        expected.append("\n".join(current) + "\n")
    return text, expected


def run_and_validate(program):
    fixture, expected = make_dynamic_fixture()
    with open("/home/user/system.log", "w") as f:
        f.write(fixture)
    shutil.rmtree("/home/user/disk_errors", ignore_errors=True)

    result = subprocess.run([program], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
    assert result.returncode == 0, f"{program} failed on a dynamic fixture: {result.stderr}"
    assert os.path.isdir("/home/user/disk_errors"), f"{program} did not create disk_errors."

    names = sorted(os.listdir("/home/user/disk_errors"))
    wanted = [f"error_{i}.log" for i in range(1, len(expected) + 1)]
    assert names == wanted, f"{program} produced {names}, expected {wanted}."
    for index, wanted_content in enumerate(expected, 1):
        path = f"/home/user/disk_errors/error_{index}.log"
        with open(path, "r") as f:
            actual = f.read()
        assert actual.strip() == wanted_content.strip(), f"{program} parsed or redacted dynamic event {index} incorrectly."
        assert "SESSION_TOKEN=" not in actual or "SESSION_TOKEN=REDACTED" in actual


def test_submitted_executable_on_dynamic_input():
    run_and_validate("/home/user/extractor")


def test_cpp_source_compiles_and_works_on_dynamic_input():
    built = "/tmp/extractor_from_submitted_source"
    result = subprocess.run(
        ["g++", "-std=c++17", "/home/user/extractor.cpp", "-o", built],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"extractor.cpp does not compile with C++17: {result.stderr}"
    run_and_validate(built)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
