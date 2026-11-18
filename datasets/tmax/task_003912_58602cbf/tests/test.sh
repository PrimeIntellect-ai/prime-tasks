#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import tarfile
from pathlib import PurePosixPath

import pytest

ARCHIVE = "/home/user/config_backup.tar"
DEST = "/home/user/safe_configs"
REPORT = "/home/user/report.txt"


def is_safe_name(name):
    path = PurePosixPath(name)
    return bool(name) and not path.is_absolute() and ".." not in path.parts


def archive_members():
    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} is missing."
    with tarfile.open(ARCHIVE, "r") as tar:
        members = tar.getmembers()
        data = {
            member.name: tar.extractfile(member).read()
            for member in members
            if member.isfile()
        }
    return members, data


def test_safe_files_extracted():
    db_conf_path = "/home/user/safe_configs/service/db.conf"
    app_conf_path = "/home/user/safe_configs/service/app.conf"

    assert os.path.exists(db_conf_path), f"Safe file {db_conf_path} was not extracted."
    assert os.path.exists(app_conf_path), f"Safe file {app_conf_path} was not extracted."

    with open(db_conf_path, "r") as f:
        assert f.read() == "db=prod", f"Content of {db_conf_path} is incorrect."

    with open(app_conf_path, "r") as f:
        assert f.read() == "port=8080", f"Content of {app_conf_path} is incorrect."


def test_archive_derived_extraction_and_metadata():
    members, data = archive_members()
    safe_files = [m for m in members if m.isfile() and is_safe_name(m.name)]
    assert safe_files, "The archive contains no safe regular files."

    expected_paths = set()
    for member in safe_files:
        output = os.path.join(DEST, *PurePosixPath(member.name).parts)
        expected_paths.add(os.path.normpath(output))
        assert os.path.isfile(output) and not os.path.islink(output), \
            f"Safe archive member {member.name} was not extracted as a regular file."
        with open(output, "rb") as f:
            assert f.read() == data[member.name], \
                f"Extracted content for {member.name} does not match the archive."
        assert int(os.stat(output).st_mtime) == int(member.mtime), \
            f"Extracted mtime for {member.name} does not match its archive metadata."

    actual_paths = set()
    assert os.path.isdir(DEST), f"Extraction directory {DEST} does not exist."
    for root, dirs, files in os.walk(DEST, followlinks=False):
        for name in dirs:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Unexpected symlink extracted at {path}."
        for name in files:
            path = os.path.normpath(os.path.join(root, name))
            assert not os.path.islink(path), f"Unexpected symlink extracted at {path}."
            actual_paths.add(path)

    assert actual_paths == expected_paths, \
        f"Extraction tree does not exactly match safe archive files. Expected {expected_paths}, got {actual_paths}."


def test_malicious_files_not_extracted():
    evil_sh_path = "/home/user/evil.sh"
    fake_shadow_path = "/etc/fake_shadow"

    assert not os.path.exists(evil_sh_path), f"Malicious file {evil_sh_path} was extracted!"
    assert not os.path.exists(fake_shadow_path), f"Malicious file {fake_shadow_path} was extracted!"


def test_no_unsafe_member_extracted_anywhere():
    members, data = archive_members()
    unsafe_files = [m for m in members if m.isfile() and not is_safe_name(m.name)]
    assert unsafe_files, "Expected unsafe members are missing from the source archive."

    # Ensure the source archive was not rewritten to hide the known malicious members.
    assert data.get("../evil.sh") == b"echo pwned"
    assert data.get("/etc/fake_shadow") == b"root:x:0:0:"

    candidates = {}
    for member in unsafe_files:
        candidates.setdefault(PurePosixPath(member.name).name, []).append(
            (member.name, data[member.name])
        )

    pruned = {"/proc", "/sys", "/dev"}
    for root, dirs, files in os.walk("/", topdown=True, followlinks=False):
        dirs[:] = [
            d for d in dirs
            if os.path.join(root, d) not in pruned
            and not os.path.islink(os.path.join(root, d))
        ]
        for filename in files:
            if filename not in candidates:
                continue
            path = os.path.join(root, filename)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            for member_name, payload in candidates[filename]:
                try:
                    if os.path.getsize(path) == len(payload):
                        with open(path, "rb") as f:
                            found = f.read()
                        assert found != payload, \
                            f"Unsafe archive member {member_name} was extracted at {path}!"
                except OSError:
                    continue


def test_report_content():
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"Report file {report_path} does not exist."

    expected_content = "Filename: db.conf\nContent: db=prod"

    with open(report_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Report content is incorrect. Expected:\n{expected_content}\nGot:\n{content}"


def test_report_is_derived_from_newest_safe_member():
    members, data = archive_members()
    safe_files = [m for m in members if m.isfile() and is_safe_name(m.name)]
    newest_mtime = max(m.mtime for m in safe_files)
    newest = [m for m in safe_files if m.mtime == newest_mtime]
    assert len(newest) == 1, "Archive has an ambiguous newest safe file."
    member = newest[0]
    expected = (
        f"Filename: {PurePosixPath(member.name).name}\nContent: ".encode("utf-8")
        + data[member.name]
    )
    assert os.path.isfile(REPORT), f"Report file {REPORT} does not exist."
    with open(REPORT, "rb") as f:
        actual = f.read().rstrip(b"\r\n")
    assert actual == expected, "Report does not describe the newest safe archive member."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
