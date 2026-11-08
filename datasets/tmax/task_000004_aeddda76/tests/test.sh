#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import shutil
import subprocess
import sys
import tarfile
import uuid
from io import BytesIO

import pytest

INCOMING_DIR = "/home/user/incoming"
PROCESSED_DIR = "/home/user/processed"
SCRIPT = "/home/user/sanitize.py"
EXPECTED = {}
RUN_DIR = None
ESCAPE_PATH = None
ABSOLUTE_PATH = None


def unsafe_path(name):
    return name.startswith("/") or ".." in name.split("/")


def archive_expectations():
    expected = {}
    for filename in sorted(os.listdir(INCOMING_DIR)):
        if not filename.endswith(".tar.gz"):
            continue
        source = os.path.join(INCOMING_DIR, filename)
        if not os.path.isfile(source):
            continue

        safe_members = []
        total_size = 0
        with tarfile.open(source, "r:gz") as tar:
            for member in tar.getmembers():
                if unsafe_path(member.name):
                    continue
                data = None
                if member.isfile():
                    extracted = tar.extractfile(member)
                    assert extracted is not None
                    data = extracted.read()
                    assert len(data) == member.size
                    total_size += member.size
                safe_members.append((member.name, member.size, member.isfile(), data))

        basename = filename[:-7]
        output_name = f"{basename}_safe_{total_size}.tar.gz"
        expected[output_name] = safe_members
    return expected


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    global EXPECTED, RUN_DIR, ESCAPE_PATH, ABSOLUTE_PATH

    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a regular file."

    probe_id = uuid.uuid4().hex
    probe_name = f"verifier_probe_{probe_id}.tar.gz"
    probe_path = os.path.join(INCOMING_DIR, probe_name)
    escape_name = f"verifier_escape_{probe_id}"
    absolute_name = f"verifier_absolute_{probe_id}"

    payloads = {
        "nested/alpha.bin": os.urandom(37),
        "plain.txt": os.urandom(19),
        "almost..": os.urandom(11),
        "dot..name/file.bin": os.urandom(7),
    }
    with tarfile.open(probe_path, "w:gz") as tar:
        for name, data in payloads.items():
            member = tarfile.TarInfo(name)
            member.size = len(data)
            tar.addfile(member, BytesIO(data))

        for name, data in [
            (f"../{escape_name}", b"TRAVERSAL"),
            ("folder/../hidden.txt", b"HIDDEN"),
            ("..", b"DOTDOT"),
            (f"/tmp/{absolute_name}", b"ABSOLUTE"),
        ]:
            member = tarfile.TarInfo(name)
            member.size = len(data)
            tar.addfile(member, BytesIO(data))

    EXPECTED = archive_expectations()

    if os.path.exists(PROCESSED_DIR):
        shutil.rmtree(PROCESSED_DIR)
    os.makedirs(PROCESSED_DIR, mode=0o777)
    os.chmod(PROCESSED_DIR, 0o777)

    RUN_DIR = f"/tmp/verifier_run_{probe_id}"
    os.makedirs(RUN_DIR, mode=0o777)
    os.chmod(RUN_DIR, 0o777)
    ESCAPE_PATH = os.path.join("/tmp", escape_name)
    ABSOLUTE_PATH = os.path.join("/tmp", absolute_name)
    for path in (ESCAPE_PATH, ABSOLUTE_PATH):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    env = os.environ.copy()
    env["HOME"] = user.pw_dir
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd=RUN_DIR,
        env=env,
        preexec_fn=demote,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"sanitize.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert not os.path.lexists(ESCAPE_PATH), "A traversal member was extracted to disk."
    assert not os.path.lexists(ABSOLUTE_PATH), "An absolute-path member was extracted to disk."
    assert os.listdir(RUN_DIR) == [], "Archive contents were extracted into the working directory."


def test_processed_files_exist():
    expected_files = [
        "archive1_safe_30.tar.gz",
        "archive2_safe_15.tar.gz",
        "archive3_safe_25.tar.gz"
    ]

    assert os.path.exists(PROCESSED_DIR), f"Processed directory {PROCESSED_DIR} does not exist."

    for f in expected_files:
        filepath = os.path.join(PROCESSED_DIR, f)
        assert os.path.exists(filepath), f"Expected output file {filepath} is missing. Check your renaming logic and size calculation."
        assert os.path.isfile(filepath), f"{filepath} is not a file."


def test_archive1_contents():
    filepath = os.path.join(PROCESSED_DIR, "archive1_safe_30.tar.gz")
    assert os.path.exists(filepath), f"File {filepath} missing."

    with tarfile.open(filepath, "r:gz") as tar:
        names = tar.getnames()
        assert len(names) == 2, f"Expected 2 files in archive1, found {len(names)}: {names}"
        assert "file1.txt" in names, "file1.txt missing from processed archive1"
        assert "dir/file2.txt" in names, "dir/file2.txt missing from processed archive1"

        assert tar.getmember("file1.txt").size == 10
        assert tar.getmember("dir/file2.txt").size == 20
        assert tar.extractfile("file1.txt").read() == b"A" * 10
        assert tar.extractfile("dir/file2.txt").read() == b"B" * 20


def test_archive2_contents():
    filepath = os.path.join(PROCESSED_DIR, "archive2_safe_15.tar.gz")
    assert os.path.exists(filepath), f"File {filepath} missing."

    with tarfile.open(filepath, "r:gz") as tar:
        names = tar.getnames()
        assert len(names) == 1, f"Expected 1 file in archive2, found {len(names)}: {names}"
        assert "safe.txt" in names, "safe.txt missing from processed archive2"
        assert "../malicious.txt" not in names, "Malicious file with directory traversal was not filtered out!"

        assert tar.getmember("safe.txt").size == 15
        assert tar.extractfile("safe.txt").read() == b"C" * 15


def test_archive3_contents():
    filepath = os.path.join(PROCESSED_DIR, "archive3_safe_25.tar.gz")
    assert os.path.exists(filepath), f"File {filepath} missing."

    with tarfile.open(filepath, "r:gz") as tar:
        names = tar.getnames()
        assert len(names) == 1, f"Expected 1 file in archive3, found {len(names)}: {names}"
        assert "log/safe.log" in names, "log/safe.log missing from processed archive3"
        assert "/etc/passwd" not in names, "Malicious file with absolute path was not filtered out!"

        assert tar.getmember("log/safe.log").size == 25
        assert tar.extractfile("log/safe.log").read() == b"D" * 25


def test_all_archives_match_incoming_bytes_and_paths():
    actual_archives = sorted(
        name for name in os.listdir(PROCESSED_DIR)
        if name.endswith(".tar.gz") and os.path.isfile(os.path.join(PROCESSED_DIR, name))
    )
    assert actual_archives == sorted(EXPECTED), (
        f"Processed archive set is wrong. Expected {sorted(EXPECTED)}, got {actual_archives}"
    )

    for output_name, expected_members in EXPECTED.items():
        output_path = os.path.join(PROCESSED_DIR, output_name)
        with tarfile.open(output_path, "r:gz") as tar:
            members = tar.getmembers()
            assert sorted(m.name for m in members) == sorted(m[0] for m in expected_members)
            actual_by_name = {member.name: member for member in members}
            for name, size, is_file, expected_data in expected_members:
                member = actual_by_name[name]
                assert member.size == size, f"Wrong size for {name} in {output_name}"
                assert member.isfile() == is_file, f"Wrong member type for {name} in {output_name}"
                if is_file:
                    extracted = tar.extractfile(member)
                    assert extracted is not None
                    assert extracted.read() == expected_data, (
                        f"File bytes for {name} in {output_name} do not match the incoming archive"
                    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
