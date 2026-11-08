#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import shutil
import subprocess
import tarfile
import tempfile

import pytest

BACKUP_ARCHIVE = "/home/user/backup.tar.gz"
REDACT_SOURCE = "/home/user/redact.c"
REDACT_EXECUTABLE = "/home/user/redact"
ARCHIVE_SCRIPT = "/home/user/archive.sh"

APP1_EXPECTED = """INFO 2023-10-01 Starting service
DEBUG USER=alice PASSWORD=[REDACTED] IP=192.168.1.5
INFO User logged in
ERROR USER=bob PASSWORD=[REDACTED] Connection failed
"""

APP2_EXPECTED = """INFO 2023-10-02 Service running normally
DEBUG USER=admin PASSWORD=[REDACTED]
INFO USER=charlie PASSWORD=[REDACTED] IP=10.0.0.2
"""


def parse_manifest(path):
    result = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                result[parts[1].lstrip("*")] = parts[0]
    return result


def expected_redaction(data):
    return re.sub(rb"PASSWORD=\\S*", b"PASSWORD=[REDACTED]", data)


def test_backup_archive_exists():
    assert os.path.isfile(BACKUP_ARCHIVE), f"Backup archive {BACKUP_ARCHIVE} does not exist."


def test_backup_contents_and_redaction():
    assert os.path.isfile(BACKUP_ARCHIVE), f"Backup archive {BACKUP_ARCHIVE} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(BACKUP_ARCHIVE, "r:gz") as tar:
                tar.extractall(path=tmpdir)
        except tarfile.TarError as e:
            pytest.fail(f"Failed to extract {BACKUP_ARCHIVE}: {e}")

        clean_logs_dir = os.path.join(tmpdir, "clean_logs")
        assert os.path.isdir(clean_logs_dir), "'clean_logs' directory not found in the archive."

        app1_path = os.path.join(clean_logs_dir, "app1.log")
        app2_path = os.path.join(clean_logs_dir, "app2.log")
        manifest_path = os.path.join(clean_logs_dir, "manifest.sha256")

        assert os.path.isfile(app1_path), "app1.log not found in clean_logs directory."
        assert os.path.isfile(app2_path), "app2.log not found in clean_logs directory."
        assert os.path.isfile(manifest_path), "manifest.sha256 not found in clean_logs directory."

        with open(app1_path, "r") as f:
            app1_content = f.read()
        assert app1_content == APP1_EXPECTED, "app1.log content was not properly redacted."

        with open(app2_path, "r") as f:
            app2_content = f.read()
        assert app2_content == APP2_EXPECTED, "app2.log content was not properly redacted."

        app1_sha256 = hashlib.sha256(app1_content.encode("utf-8")).hexdigest()
        app2_sha256 = hashlib.sha256(app2_content.encode("utf-8")).hexdigest()
        manifest_dict = parse_manifest(manifest_path)

        assert "app1.log" in manifest_dict, "app1.log missing from manifest.sha256"
        assert "app2.log" in manifest_dict, "app2.log missing from manifest.sha256"
        assert manifest_dict["app1.log"] == app1_sha256, "app1.log checksum in manifest does not match actual checksum."
        assert manifest_dict["app2.log"] == app2_sha256, "app2.log checksum in manifest does not match actual checksum."


def test_required_artifacts_and_redactor_behavior():
    assert os.path.isfile(REDACT_SOURCE), f"{REDACT_SOURCE} does not exist."
    assert os.path.isfile(REDACT_EXECUTABLE), f"{REDACT_EXECUTABLE} does not exist."
    assert os.access(REDACT_EXECUTABLE, os.X_OK), f"{REDACT_EXECUTABLE} is not executable."
    assert os.path.isfile(ARCHIVE_SCRIPT), f"{ARCHIVE_SCRIPT} does not exist."

    with open(REDACT_EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{REDACT_EXECUTABLE} is not a compiled executable."

    token = secrets.token_hex(16).encode("ascii")
    redactor_input = (
        b"ordinary line without credentials\n"
        b"USER=dynamic PASSWORD=" + token + b" IP=203.0.113.8\n"
        b"PASSWORD=second_secret\tSTATUS=ok\n"
        b"lowercase password=must_stay\n"
    )
    expected = expected_redaction(redactor_input)

    result = subprocess.run(
        [REDACT_EXECUTABLE],
        input=redactor_input,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, f"redact executable failed: {result.stderr.decode(errors='replace')}"
    assert result.stdout == expected, "redact executable did not correctly process generated input."

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "redact-rebuilt")
        compile_result = subprocess.run(
            ["gcc", REDACT_SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert compile_result.returncode == 0, f"redact.c did not compile: {compile_result.stderr.decode(errors='replace')}"
        rebuilt_result = subprocess.run(
            [rebuilt],
            input=redactor_input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert rebuilt_result.returncode == 0, "Program rebuilt from redact.c failed."
        assert rebuilt_result.stdout == expected, "Program rebuilt from redact.c redacted generated input incorrectly."


def test_archive_script_on_generated_logs():
    raw_logs = "/home/user/raw_logs"
    clean_logs = "/home/user/clean_logs"
    token = secrets.token_hex(12)
    names = [f"generated_{token}_a.log", f"generated_{token}_b.log"]
    secrets_used = [secrets.token_hex(18), secrets.token_hex(18)]
    inputs = {
        names[0]: (
            f"INFO generated test {token}\n"
            f"USER=tester PASSWORD={secrets_used[0]} IP=198.51.100.4\n"
            "INFO complete\n"
        ).encode("utf-8"),
        names[1]: (
            f"PASSWORD={secrets_used[1]} STATUS=failed\n"
            "A line which must remain unchanged\n"
        ).encode("utf-8"),
    }

    shutil.rmtree(raw_logs, ignore_errors=True)
    os.makedirs(raw_logs)
    for name, content in inputs.items():
        with open(os.path.join(raw_logs, name), "wb") as f:
            f.write(content)
    with open(os.path.join(raw_logs, f"ignored_{token}.txt"), "wb") as f:
        f.write(b"PASSWORD=this_non_log_file_must_not_be_archived\n")

    shutil.rmtree(clean_logs, ignore_errors=True)
    try:
        os.remove(BACKUP_ARCHIVE)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    result = subprocess.run(
        ["bash", ARCHIVE_SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, f"archive.sh failed: {result.stderr.decode(errors='replace')}"
    assert os.path.isfile(BACKUP_ARCHIVE), "archive.sh did not create backup.tar.gz."

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(BACKUP_ARCHIVE, "r:gz") as tar:
                tar.extractall(tmpdir)
        except tarfile.TarError as e:
            pytest.fail(f"archive.sh produced an invalid tarball: {e}")

        archived_clean = os.path.join(tmpdir, "clean_logs")
        assert os.path.isdir(archived_clean), "Generated archive lacks clean_logs directory."
        manifest_path = os.path.join(archived_clean, "manifest.sha256")
        assert os.path.isfile(manifest_path), "Generated archive lacks manifest.sha256."
        assert not os.path.exists(os.path.join(archived_clean, f"ignored_{token}.txt")), "A non-.log file was archived."

        manifest = parse_manifest(manifest_path)
        assert set(manifest) == set(names), "Manifest does not list exactly the generated .log files."

        for name, original in inputs.items():
            archived_path = os.path.join(archived_clean, name)
            assert os.path.isfile(archived_path), f"Generated log {name} is missing from the archive."
            with open(archived_path, "rb") as f:
                actual = f.read()
            assert actual == expected_redaction(original), f"Generated log {name} was not correctly redacted."
            for secret in secrets_used:
                assert secret.encode("ascii") not in actual, f"Unredacted password remains in {name}."
            assert manifest[name] == hashlib.sha256(actual).hexdigest(), f"Checksum for {name} is incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
