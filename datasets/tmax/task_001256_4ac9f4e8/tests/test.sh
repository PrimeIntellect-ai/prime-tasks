#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import shutil
import stat
import subprocess
import tempfile
import uuid

PROJECT = "/home/user/project"


def test_secret_file_not_overwritten():
    secret_path = "/home/user/secret.txt"
    assert os.path.isfile(secret_path), f"Secret file {secret_path} is missing."
    with open(secret_path, "r") as f:
        content = f.read().strip()
    assert content == "SAFE", "The secret file was overwritten! The extractor vulnerability was not properly fixed."


def test_extractor_executable_exists():
    extractor_path = os.path.join(PROJECT, "extractor")
    assert os.path.isfile(extractor_path), f"Executable {extractor_path} is missing."
    assert os.access(extractor_path, os.X_OK), f"File {extractor_path} is not executable."
    with open(extractor_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "extractor is not a compiled executable."


def test_extractor_source_and_behavior():
    source_path = os.path.join(PROJECT, "extractor.c")
    submitted_path = os.path.join(PROJECT, "extractor")
    assert os.path.isfile(source_path), f"Source file {source_path} is missing."

    compiled_path = os.path.join("/tmp", "extractor-from-source-" + uuid.uuid4().hex)
    try:
        result = subprocess.run(
            ["gcc", "-std=c11", source_path, "-o", compiled_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, "extractor.c does not compile:\n" + result.stderr.decode(errors="replace")
        os.chmod(compiled_path, 0o755)

        for binary in (submitted_path, compiled_path):
            _exercise_extractor(binary)
    finally:
        try:
            os.unlink(compiled_path)
        except FileNotFoundError:
            pass


def _exercise_extractor(binary):
    account = pwd.getpwnam("user")
    uid, gid = account.pw_uid, account.pw_gid
    case_dir = tempfile.mkdtemp(prefix="extractor-verification-", dir="/tmp")
    try:
        extract_dir = os.path.join(case_dir, "out")
        odd_dir = os.path.join(extract_dir, "x..")
        os.mkdir(extract_dir)
        os.mkdir(odd_dir)

        for path in (case_dir, extract_dir, odd_dir):
            os.chown(path, uid, gid)
            os.chmod(path, 0o755)

        parent_target = os.path.join(case_dir, "parent-target")
        absolute_target = os.path.join(case_dir, "absolute-target")
        for target in (parent_target, absolute_target):
            with open(target, "wb") as f:
                f.write(b"UNCHANGED")
            os.chown(target, uid, gid)
            os.chmod(target, 0o644)

        token = uuid.uuid4().hex
        valid1 = "valid_" + token + "_one"
        valid2 = "valid_" + token + "_two"
        valid3 = "valid_" + token + "_three"
        entries = [
            ("../parent-target", b"PARENT_TRAVERSAL_DATA"),
            (valid1, b"first valid payload\n"),
            (absolute_target, b"ABSOLUTE_PATH_DATA"),
            (valid2, b"second valid payload"),
            ("x../forbidden", b"SUBSTRING_TRAVERSAL_DATA"),
            (valid3, b"third valid payload\x00with binary data"),
        ]
        archive = b"".join(
            name.encode() + b" " + str(len(data)).encode() + b"\n" + data
            for name, data in entries
        )

        def demote():
            os.setgroups([])
            os.setgid(gid)
            os.setuid(uid)

        result = subprocess.run(
            [binary],
            input=archive,
            cwd=extract_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=8,
            preexec_fn=demote,
        )
        assert result.returncode == 0, f"{binary} failed on a generated archive: {result.stderr.decode(errors='replace')}"

        with open(parent_target, "rb") as f:
            assert f.read() == b"UNCHANGED", "A ../ entry was written outside the extraction directory."
        with open(absolute_target, "rb") as f:
            assert f.read() == b"UNCHANGED", "An absolute-path entry was written."
        assert not os.path.exists(os.path.join(odd_dir, "forbidden")), "A filename containing ../ was not skipped."

        expected = {
            valid1: b"first valid payload\n",
            valid2: b"second valid payload",
            valid3: b"third valid payload\x00with binary data",
        }
        for name, data in expected.items():
            path = os.path.join(extract_dir, name)
            assert os.path.isfile(path), f"Valid entry {name} was not extracted after skipped entries."
            with open(path, "rb") as f:
                assert f.read() == data, f"Extracted contents for {name} are incorrect."
    finally:
        shutil.rmtree(case_dir, ignore_errors=True)


def test_extracted_files_exist_and_contents():
    expected = {
        "backup.conf": b"app.log\nmain.c\n",
        "app.log": b"hello world\n",
        "main.c": b"int main(){}\n",
    }
    for fname, expected_content in expected.items():
        path = os.path.join(PROJECT, fname)
        assert os.path.isfile(path), f"Extracted file {path} is missing."
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Extracted file {path} has incorrect contents."


def test_backup_dir_and_hardlinks():
    backup_dir = os.path.join(PROJECT, "backup_dir")
    assert os.path.isdir(backup_dir), f"Backup directory {backup_dir} is missing."

    expected_files = ["app.log", "main.c"]
    for fname in expected_files:
        orig_path = os.path.join(PROJECT, fname)
        backup_path = os.path.join(backup_dir, fname)

        assert os.path.isfile(backup_path), f"Backup file {backup_path} is missing."

        orig_stat = os.stat(orig_path)
        backup_stat = os.stat(backup_path)

        assert orig_stat.st_ino == backup_stat.st_ino, f"{backup_path} is not a hard link to {orig_path}."
        assert orig_stat.st_nlink >= 2, f"{orig_path} does not have the expected number of hard links."


def test_success_log():
    log_path = os.path.join(PROJECT, "success.log")
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "COMPLETED", f"Expected success.log to contain 'COMPLETED', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
