#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tarfile

import pytest


def test_metadata_report_exists_and_correct():
    report_path = "/home/user/metadata_report.json"

    assert os.path.exists(report_path), f"The expected output file {report_path} does not exist."
    assert os.path.isfile(report_path), f"The path {report_path} is not a file."

    try:
        with open(report_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {report_path} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {report_path}: {e}")

    expected_data = {
        "/etc/passwd": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        "/etc/hostname": "fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321",
        "/var/www/html/index.html": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
        "/root/.bashrc": "cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe"
    }

    assert isinstance(data, dict), f"The JSON data in {report_path} should be a dictionary, but got {type(data).__name__}."

    expected_keys = set(expected_data.keys())
    actual_keys = set(data.keys())

    missing_keys = expected_keys - actual_keys
    extra_keys = actual_keys - expected_keys

    assert not missing_keys, f"Missing expected file paths in the output: {missing_keys}"
    assert not extra_keys, f"Found unexpected file paths in the output: {extra_keys}"

    for key, expected_value in expected_data.items():
        actual_value = data[key]
        assert actual_value == expected_value, f"Checksum for {key} is incorrect. Expected '{expected_value}', got '{actual_value}'."


def _inner_archive(logs):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        for name, text in logs.items():
            compressed = gzip.compress(text.encode("utf-8"))
            info = tarfile.TarInfo(name=name)
            info.size = len(compressed)
            archive.addfile(info, io.BytesIO(compressed))
    return output.getvalue()


def _write_dynamic_archive(path):
    token = secrets.token_hex(8)
    expected = {
        f"/srv/recovery/{token}/alpha.conf": secrets.token_hex(32),
        f"/srv/recovery/{token}/beta.db": secrets.token_hex(32),
        f"/opt/archive/{token}/gamma.key": secrets.token_hex(32),
        f"/var/lib/archive/{token}/delta.txt": secrets.token_hex(32),
    }

    node1 = _inner_archive({
        "./app_log_01.txt.gz": (
            "Info: dynamic verification log\n"
            f"[METADATA-EXPORT] file={list(expected)[0]} checksum={expected[list(expected)[0]]}\n"
            "Warning: unrelated text\n"
        ),
        "./app_log_02.txt.gz": (
            f"[METADATA-EXPORT] file={list(expected)[1]} checksum={expected[list(expected)[1]]}\n"
        ),
    })
    node2 = _inner_archive({
        "./app_log_01.txt.gz": (
            "Debug: another log\n"
            f"[METADATA-EXPORT] file={list(expected)[2]} checksum={expected[list(expected)[2]]}\n"
            f"[METADATA-EXPORT] file={list(expected)[3]} checksum={expected[list(expected)[3]]}\n"
        ),
        "./readme.txt.gz": gzip.compress(b"This compressed file contains no metadata.\n"),
    })

    with tarfile.open(path, mode="w") as outer:
        for name, payload in (("node1_logs.tar.gz", node1), ("node2_logs.tar.gz", node2)):
            info = tarfile.TarInfo(name=name)
            info.size = len(payload)
            outer.addfile(info, io.BytesIO(payload))

    return expected


def _extracted_artifacts():
    target_names = {
        "node1_logs.tar.gz",
        "node2_logs.tar.gz",
        "app_log_01.txt.gz",
        "app_log_02.txt.gz",
        "readme.txt.gz",
    }
    found = set()
    for root in ("/home/user", "/tmp", "/var/tmp", "/dev/shm"):
        if not os.path.isdir(root):
            continue
        for directory, _, files in os.walk(root):
            for filename in files:
                candidate = os.path.join(directory, filename)
                if filename in target_names and candidate != "/home/user/backup_archive.tar":
                    found.add(candidate)
    return found


def test_python_script_executes_on_unseen_nested_archive_without_extracting():
    archive_path = Path("/home/user/backup_archive.tar")
    report_path = Path("/home/user/metadata_report.json")
    scripts = sorted(
        p for p in Path("/home/user").rglob("*.py")
        if p.is_file()
    )
    assert scripts, "No Python script was written under /home/user."

    original_archive = archive_path.read_bytes()
    original_report = report_path.read_bytes()
    wrapper = Path("/tmp/run_submission_stream_check.py")
    wrapper.write_text(
        "import os, runpy, shutil, tarfile\n"
        "def blocked(*args, **kwargs):\n"
        "    raise RuntimeError('Extracting archive members to disk is forbidden')\n"
        "tarfile.TarFile.extract = blocked\n"
        "tarfile.TarFile.extractall = blocked\n"
        "shutil.unpack_archive = blocked\n"
        "runpy.run_path(os.environ['SUBMISSION_SCRIPT'], run_name='__main__')\n"
    )

    failures = []
    try:
        expected = _write_dynamic_archive(archive_path)
        preexisting_artifacts = _extracted_artifacts()

        for script in scripts:
            if report_path.exists():
                report_path.unlink()

            env = os.environ.copy()
            env["SUBMISSION_SCRIPT"] = str(script)
            try:
                result = subprocess.run(
                    [sys.executable, str(wrapper)],
                    cwd="/home/user",
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20,
                )
            except subprocess.TimeoutExpired:
                failures.append(f"{script}: timed out")
                continue

            new_artifacts = _extracted_artifacts() - preexisting_artifacts
            if new_artifacts:
                failures.append(f"{script}: extracted archive members to disk: {sorted(new_artifacts)}")
                continue
            if result.returncode != 0:
                failures.append(f"{script}: exited with status {result.returncode}: {result.stderr[-500:]}")
                continue
            if not report_path.is_file():
                failures.append(f"{script}: did not create metadata_report.json")
                continue
            try:
                actual = json.loads(report_path.read_text())
            except Exception as exc:
                failures.append(f"{script}: produced invalid JSON: {exc}")
                continue
            if actual == expected:
                return
            failures.append(f"{script}: report did not match metadata derived from the unseen archive")

        pytest.fail("No submitted Python script passed behavioral verification. " + " | ".join(failures))
    finally:
        archive_path.write_bytes(original_archive)
        report_path.write_bytes(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
