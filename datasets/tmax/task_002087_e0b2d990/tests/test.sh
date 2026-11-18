#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time

import pytest

ARCHIVE = "/home/user/final_backup.fsa"
TARGET = "/home/user/legacy_data"
BINARY = "/home/user/bin/fast-archiver"
SCRIPT = "/home/user/backup_daemon.sh"
CONFIG = "/home/user/spool/backup.conf"


def read_archive(path):
    assert os.path.isfile(path), f"Archive file missing: {path}"
    with tempfile.NamedTemporaryFile(suffix=".tar") as tar_out:
        result = subprocess.run(
            ["zstd", "-q", "-d", "-c", path],
            stdout=tar_out,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert result.returncode == 0, f"Archive is not a valid zstd stream: {result.stderr.decode(errors='replace')}"
        tar_out.flush()
        result = subprocess.run(
            ["tar", "-tf", tar_out.name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"Decompressed archive is not valid tar: {result.stderr.decode(errors='replace')}"
        tar_out.seek(0)
        with tarfile.open(fileobj=tar_out, mode="r:") as tf:
            members = tf.getmembers()
            files = {}
            directories = set()
            for member in members:
                name = member.name.lstrip("./")
                assert name and not name.startswith("/") and ".." not in name.split("/"), f"Unsafe archive member: {member.name}"
                if member.isdir():
                    directories.add(name.rstrip("/"))
                elif member.isfile():
                    assert name not in files, f"Duplicate archive member: {name}"
                    extracted = tf.extractfile(member)
                    assert extracted is not None
                    files[name] = extracted.read()
            return files, directories


def expected_tree(root):
    result = {}
    for current, _, names in os.walk(root):
        for name in names:
            path = os.path.join(current, name)
            if os.path.isfile(path):
                result[path.lstrip("/")] = open(path, "rb").read()
    return result


def kill_existing_daemons():
    own_pid = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == own_pid:
            continue
        try:
            cmdline = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ")
            if b"/home/user/backup_daemon.sh" in cmdline:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.5)


def test_archive_exists_and_size_metric():
    archive_path = "/home/user/final_backup.fsa"
    assert os.path.isfile(archive_path), f"Archive file missing: {archive_path}"

    file_size = os.path.getsize(archive_path)
    threshold = 4500000
    assert file_size <= threshold, f"Archive size is {file_size} bytes, which exceeds the threshold of {threshold} bytes. The archiver may not have been compiled with the correct optimization flags."


def test_files_converted_to_utf8():
    suffix = "éàçù\n".encode("utf-8")
    for i in range(1, 51):
        file_path = f"/home/user/legacy_data/project_a/file_{i}.txt"
        assert os.path.isfile(file_path), f"File missing: {file_path}"

        with open(file_path, "rb") as f:
            content = f.read()

        try:
            content.decode('utf-8')
        except UnicodeDecodeError:
            pytest.fail(f"File {file_path} is not valid UTF-8. The encoding conversion step failed or was not performed.")

        assert content.endswith(suffix), f"File {file_path} does not contain the expected converted ISO-8859-1 characters"
        encoded_body = b"".join(content[:-len(suffix)].split())
        try:
            decoded = base64.b64decode(encoded_body, validate=True)
        except Exception as exc:
            pytest.fail(f"File {file_path} no longer contains its generated base64 data: {exc}")
        assert len(decoded) == 200000, f"File {file_path} was truncated or replaced"


def test_daemon_script_exists():
    script_path = "/home/user/backup_daemon.sh"
    assert os.path.isfile(script_path), f"Backup daemon script missing: {script_path}"
    result = subprocess.run(["bash", "-n", script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f"Backup daemon is not valid Bash: {result.stderr.decode(errors='replace')}"


def test_fast_archiver_binary_exists():
    binary_path = "/home/user/bin/fast-archiver"
    assert os.path.isfile(binary_path), f"Compiled fast-archiver binary missing at expected path: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"fast-archiver binary at {binary_path} is not executable"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast-archiver is not a compiled ELF binary"

    makefile = open("/app/fast-archiver-1.0/Makefile", encoding="utf-8").read()
    assert not re.search(r"^\s*CC\s*=\s*gccc\s*$", makefile, re.MULTILINE), "The broken compiler setting was not fixed"
    assert re.search(r"-O(?:2|3|fast)\b", makefile), "The Makefile does not enable high optimization"


def test_final_archive_contains_complete_converted_target():
    files, directories = read_archive(ARCHIVE)
    root_name = TARGET.lstrip("/")
    assert root_name in directories or any(name.startswith(root_name + "/") for name in files), "Archive does not contain the target directory"

    expected = expected_tree(TARGET)
    archived_target = {name: data for name, data in files.items() if name == root_name or name.startswith(root_name + "/")}
    assert set(archived_target) == set(expected), "Archive does not contain exactly the target directory's files"
    for name, data in expected.items():
        assert archived_target[name] == data, f"Archived file differs from converted source: {name}"
        if name.endswith(".txt"):
            archived_target[name].decode("utf-8")


def test_fast_archiver_executes_and_creates_valid_archive():
    with tempfile.TemporaryDirectory() as work:
        source = os.path.join(work, "input")
        os.mkdir(source)
        payloads = {
            "unpredictable.bin": os.urandom(8192),
            "message.txt": ("archiver behavior test é\n" * 100).encode("utf-8"),
        }
        for name, data in payloads.items():
            open(os.path.join(source, name), "wb").write(data)
        output = os.path.join(work, "result.fsa")
        result = subprocess.run([BINARY, source, output], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        assert result.returncode == 0, f"fast-archiver failed when executed: {result.stderr.decode(errors='replace')}"
        files, _ = read_archive(output)
        prefix = source.lstrip("/") + "/"
        actual = {name[len(prefix):]: data for name, data in files.items() if name.startswith(prefix)}
        assert actual == payloads, "fast-archiver output did not preserve its input directory"


def test_backup_daemon_pipeline_on_fresh_trigger():
    kill_existing_daemons()
    saved_archive = None
    saved_config = None
    if os.path.exists(ARCHIVE):
        saved_archive = tempfile.NamedTemporaryFile(delete=False)
        saved_archive.close()
        shutil.copy2(ARCHIVE, saved_archive.name)
    if os.path.exists(CONFIG):
        saved_config = tempfile.NamedTemporaryFile(delete=False)
        saved_config.close()
        shutil.copy2(CONFIG, saved_config.name)
        os.unlink(CONFIG)

    process = None
    try:
        with tempfile.TemporaryDirectory() as target:
            latin_text = b"daemon test: \xe9\xe0\xe7\xf9\n"
            expected_text = latin_text.decode("iso-8859-1").encode("utf-8")
            binary_data = os.urandom(4096)
            open(os.path.join(target, "legacy.txt"), "wb").write(latin_text)
            open(os.path.join(target, "keep.bin"), "wb").write(binary_data)
            if os.path.exists(ARCHIVE):
                os.unlink(ARCHIVE)

            process = subprocess.Popen(["bash", SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(0.5)
            with open(CONFIG, "w", encoding="utf-8") as f:
                f.write(f"TARGET_DIR={target}\nEXCLUDE_EXT=.tmp\n")

            deadline = time.time() + 30
            while time.time() < deadline and not os.path.isfile(ARCHIVE):
                time.sleep(0.25)
            assert os.path.isfile(ARCHIVE), "Backup daemon did not react to a fresh backup.conf trigger"
            assert open(os.path.join(target, "legacy.txt"), "rb").read() == expected_text, "Daemon did not convert ISO-8859-1 text to UTF-8"

            files, _ = read_archive(ARCHIVE)
            prefix = target.lstrip("/") + "/"
            actual = {name[len(prefix):]: data for name, data in files.items() if name.startswith(prefix)}
            assert actual == {"legacy.txt": expected_text, "keep.bin": binary_data}, "Daemon archive does not contain the converted target files"
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
        kill_existing_daemons()
        if os.path.exists(CONFIG):
            os.unlink(CONFIG)
        if saved_config is not None:
            shutil.copy2(saved_config.name, CONFIG)
            os.unlink(saved_config.name)
        if saved_archive is not None:
            shutil.copy2(saved_archive.name, ARCHIVE)
            os.unlink(saved_archive.name)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
