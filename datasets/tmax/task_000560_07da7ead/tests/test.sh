#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import shutil
import subprocess
import tempfile
import time

BACKUP = "/home/user/backup.gz"
SOURCE = "/app/backup_agent/agent.c"
AGENT = "/app/backup_agent/agent"
CONFIGS = "/app/configs"


def test_backup_file_size():
    # Preserve the original final-state assertions.
    assert os.path.exists(BACKUP), f"Expected backup file {BACKUP} does not exist."
    assert os.path.isfile(BACKUP), f"Expected {BACKUP} to be a regular file."

    file_size = os.path.getsize(BACKUP)
    threshold = 1000
    assert file_size < threshold, (
        f"Backup file size is {file_size} bytes, which is >= {threshold} bytes. "
        "This indicates the symlink loop was not properly fixed or "
        "the backup contains duplicate/incorrect data."
    )
    assert file_size > 0, "Backup file is empty (0 bytes), which means no data was processed."


def test_source_and_compiled_agent_process_only_regular_files():
    assert os.path.isfile(SOURCE), f"Missing source file {SOURCE}"
    assert os.path.isfile(AGENT), f"Missing compiled agent {AGENT}"
    assert os.access(AGENT, os.X_OK), f"Compiled agent {AGENT} is not executable"
    with open(AGENT, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AGENT} is not a compiled ELF executable"

    source = open(SOURCE, encoding="utf-8", errors="replace").read()
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    code = re.sub(r"//.*", "", code)
    assert re.search(r"\blstat\s*\(", code), "agent.c does not use lstat()"
    assert re.search(r"\bS_ISLNK\s*\(", code), "agent.c does not detect symbolic links with S_ISLNK()"

    rebuilt = "/tmp/verifier_agent"
    compile_result = subprocess.run(
        ["gcc", "-o", rebuilt, SOURCE, "-lz"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "agent.c does not compile with 'gcc -o agent agent.c -lz':\n"
        + compile_result.stderr
    )

    saved_configs = tempfile.mkdtemp(prefix="saved_configs_")
    os.rmdir(saved_configs)
    os.rename(CONFIGS, saved_configs)
    os.mkdir(CONFIGS)
    try:
        header = b"1234567890123456"
        bodies = [b"config_data_1\n", b"config_data_2\n"]
        with open(os.path.join(CONFIGS, "conf1.dat"), "wb") as f:
            f.write(header + bodies[0])
        with open(os.path.join(CONFIGS, "conf2.dat"), "wb") as f:
            f.write(header + bodies[1])
        os.symlink(CONFIGS, os.path.join(CONFIGS, "legacy"))

        expected = {bodies[0] + bodies[1], bodies[1] + bodies[0]}
        for executable in (AGENT, rebuilt):
            if os.path.lexists(BACKUP):
                os.unlink(BACKUP)
            try:
                result = subprocess.run(
                    [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    timeout=5
                )
            except subprocess.TimeoutExpired:
                raise AssertionError(f"{executable} did not terminate; it likely followed the symlink loop")
            assert result.returncode == 0, f"{executable} exited with status {result.returncode}"
            assert os.path.isfile(BACKUP), f"{executable} did not create {BACKUP}"
            size = os.path.getsize(BACKUP)
            assert 0 < size < 1000, f"Generated backup has invalid size {size}"
            try:
                with gzip.open(BACKUP, "rb") as f:
                    contents = f.read()
            except Exception as exc:
                raise AssertionError(f"Generated backup is not a valid gzip stream: {exc}")
            assert contents in expected, (
                "Decompressed backup does not contain exactly the two header-stripped "
                f"regular-file bodies; got {contents!r}"
            )
    finally:
        shutil.rmtree(CONFIGS, ignore_errors=True)
        os.rename(saved_configs, CONFIGS)


def test_nginx_upload_logging_and_services():
    syntax = subprocess.run(
        ["nginx", "-t", "-c", "/app/nginx/nginx.conf"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert syntax.returncode == 0, "Invalid Nginx configuration:\n" + syntax.stderr

    redis = subprocess.run(
        ["redis-cli", "-p", "6379", "ping"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5
    )
    assert redis.returncode == 0 and redis.stdout.strip() == "PONG", "Redis is not running on port 6379"

    log_path = "/app/logs/update.log"
    before = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    request_body = "target=/app/configs"
    upload = subprocess.run(
        ["curl", "-sS", "-o", "/tmp/upload_response", "-w", "%{http_code}",
         "-X", "POST", "--data", request_body, "http://127.0.0.1:8080/upload"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert upload.returncode == 0, "Nginx is not running on port 8080: " + upload.stderr
    assert upload.stdout.strip() == "200", f"POST /upload returned HTTP {upload.stdout.strip()} instead of 200"

    time.sleep(0.5)
    assert os.path.isfile(log_path), f"Nginx did not create {log_path}"
    with open(log_path, "rb") as f:
        f.seek(before)
        appended = f.read()
    assert appended, "POST /upload did not append a record to update.log"
    assert appended.count(b"\n") >= 2, "The upload record in update.log is not in a multi-line format"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
