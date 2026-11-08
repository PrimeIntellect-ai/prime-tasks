#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import signal
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request
from pathlib import PurePosixPath

import pytest

SOURCE_ARCHIVE = "/home/user/docs_archive.tar.gz"
REPORT_PATH = "/home/user/update_report.json"
UPDATED_ARCHIVE_PATH = "/home/user/updated_docs.tar.gz"
SERVER_URL = "http://localhost:8080/update_report.json"
OLD_URL = b"http://api.old.local/v1/"
NEW_URL = b"https://api.new.local/v2/"

FILLER = b"Some extra filler documentation line.\n" * 100
ORIGINAL_FILES = {
    "docs/api/endpoints.md": (
        b"Title: API Endpoints\nVersion: 1.0\nStatus: Active\nAuthor: Bob\n---\n"
        b"Use http://api.old.local/v1/users to get users.\n"
        b"Use http://api.old.local/v1/auth to login.\n" + FILLER
    ),
    "docs/api/new_endpoints.md": (
        b"Title: New API Endpoints\nVersion: 2.0\nStatus: Active\nAuthor: Alice\n---\n"
        b"Use https://api.new.local/v2/users to get users.\n"
        b"Use http://api.old.local/v1/legacy just in case.\n" + FILLER
    ),
    "docs/guides/setup.md": (
        b"Title: Setup Guide\nVersion: 1.0\nStatus: Active\nAuthor: Charlie\n---\n"
        b"Download from http://api.old.local/v1/downloads.\n" + FILLER
    ),
    "docs/readme.md": (
        b"Title: Readme\nVersion: 1.1\nStatus: Deprecated\nAuthor: Admin\n---\n"
        b"Nothing to see here.\n" + FILLER
    ),
}


def read_regular_files(archive_path):
    result = {}
    with tarfile.open(archive_path, "r:gz") as tar:
        for member in tar.getmembers():
            if member.isfile():
                assert member.name not in result, f"Duplicate archive member: {member.name}"
                extracted = tar.extractfile(member)
                assert extracted is not None
                result[member.name] = extracted.read()
    return result


def transform_status_lines(data):
    output = []
    for line in data.splitlines(keepends=True):
        ending = b""
        body = line
        if line.endswith(b"\r\n"):
            body, ending = line[:-2], b"\r\n"
        elif line.endswith(b"\n") or line.endswith(b"\r"):
            body, ending = line[:-1], line[-1:]
        if body == b"Status: Active":
            body = b"Status: Deprecated"
        output.append(body + ending)
    return b"".join(output)


def derive_expected():
    source_files = read_regular_files(SOURCE_ARCHIVE)
    expected_report = {}
    expected_files = {}
    for path, data in source_files.items():
        if not path.endswith(".md"):
            continue
        first_five = data.splitlines()[:5]
        if any(b"Version: 1.0" in line for line in first_five):
            expected_report[path] = data.count(OLD_URL)
            expected_files[path] = transform_status_lines(data).replace(OLD_URL, NEW_URL)
    return expected_report, expected_files


def validate_artifacts(expected_report, expected_files):
    try:
        with open(REPORT_PATH, "r", encoding="utf-8") as f:
            report = json.load(f)
        if report != expected_report or type(report) is not dict:
            return False
        with tarfile.open(UPDATED_ARCHIVE_PATH, "r:gz") as tar:
            regular = {}
            for member in tar.getmembers():
                path = PurePosixPath(member.name)
                if path.is_absolute() or ".." in path.parts:
                    return False
                if member.isdir():
                    continue
                if not member.isfile() or member.name in regular:
                    return False
                extracted = tar.extractfile(member)
                if extracted is None:
                    return False
                regular[member.name] = extracted.read()
        return regular == expected_files
    except (OSError, ValueError, json.JSONDecodeError, tarfile.TarError):
        return False


def has_memory_efficient_io(source):
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return False

    stream_vars = set()
    mmap_names = set()
    mmap_modules = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "mmap":
                    mmap_modules.add(alias.asname or "mmap")
        elif isinstance(node, ast.ImportFrom) and node.module == "mmap":
            for alias in node.names:
                if alias.name == "mmap":
                    mmap_names.add(alias.asname or alias.name)
        elif isinstance(node, ast.With):
            for item in node.items:
                call = item.context_expr
                if isinstance(call, ast.Call) and item.optional_vars is not None:
                    func = call.func
                    is_stream = (
                        isinstance(func, ast.Name) and func.id == "open"
                    ) or (
                        isinstance(func, ast.Attribute) and func.attr == "extractfile"
                    )
                    if is_stream and isinstance(item.optional_vars, ast.Name):
                        stream_vars.add(item.optional_vars.id)
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value, ast.Call):
                func = value.func
                is_stream = (
                    isinstance(func, ast.Name) and func.id == "open"
                ) or (
                    isinstance(func, ast.Attribute) and func.attr == "extractfile"
                )
                if is_stream:
                    for target in targets:
                        if isinstance(target, ast.Name):
                            stream_vars.add(target.id)

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name) and func.id in mmap_names:
                return True
            if (isinstance(func, ast.Attribute) and func.attr == "mmap" and
                    isinstance(func.value, ast.Name) and func.value.id in mmap_modules):
                return True
            if isinstance(func, ast.Attribute) and func.attr == "readline":
                if isinstance(func.value, ast.Name) and func.value.id in stream_vars:
                    return True
        elif isinstance(node, (ast.For, ast.AsyncFor)):
            if isinstance(node.iter, ast.Name) and node.iter.id in stream_vars:
                return True
            if isinstance(node.iter, ast.Call):
                func = node.iter.func
                if isinstance(func, ast.Name) and func.id == "open":
                    return True
    return False


def candidate_scripts():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {".cache", ".local", "__pycache__"}]
        for filename in files:
            if not filename.endswith(".py"):
                continue
            path = os.path.join(root, filename)
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "r", encoding="utf-8") as f:
                    source = f.read()
            except (OSError, UnicodeDecodeError):
                continue
            required = ("docs_archive.tar.gz", "update_report.json", "updated_docs.tar.gz")
            if all(token in source for token in required) and has_memory_efficient_io(source):
                candidates.append(path)
    return sorted(candidates)


def run_candidate(path):
    for output in (REPORT_PATH, UPDATED_ARCHIVE_PATH):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass
    proc = subprocess.Popen(
        [sys.executable, path], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, start_new_session=True
    )
    try:
        proc.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.communicate()


def test_source_archive_is_original_and_expected_is_derived_from_it():
    assert os.path.exists(SOURCE_ARCHIVE)
    assert read_regular_files(SOURCE_ARCHIVE) == ORIGINAL_FILES, "The input archive was altered."
    report, files = derive_expected()
    assert report == {"docs/api/endpoints.md": 2, "docs/guides/setup.md": 1}
    assert set(files) == set(report)


def test_processing_script_exists_uses_streaming_or_mmap_and_reproduces_artifacts():
    expected_report, expected_files = derive_expected()
    candidates = candidate_scripts()
    assert candidates, "No Python processing script using mmap or streaming line-by-line I/O was found."
    for path in candidates:
        run_candidate(path)
        if validate_artifacts(expected_report, expected_files):
            assert read_regular_files(SOURCE_ARCHIVE) == ORIGINAL_FILES, "The script altered its input archive."
            return
    pytest.fail("No qualifying Python script reproduced the required report and archive when executed.")


def test_report_exists_and_correct():
    expected_data, _ = derive_expected()
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {REPORT_PATH} is not valid JSON.")
    assert type(report_data) is dict
    assert report_data == expected_data, f"Report data {report_data} does not match expected {expected_data}."
    assert report_data == {"docs/api/endpoints.md": 2, "docs/guides/setup.md": 1}
    assert all(type(path) is str and type(count) is int for path, count in report_data.items())


def test_updated_archive_exists_and_correct():
    expected_report, expected_files = derive_expected()
    assert os.path.exists(UPDATED_ARCHIVE_PATH), f"Updated archive {UPDATED_ARCHIVE_PATH} does not exist."
    assert tarfile.is_tarfile(UPDATED_ARCHIVE_PATH), f"{UPDATED_ARCHIVE_PATH} is not a valid tar file."

    with tarfile.open(UPDATED_ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()
        names = [m.name for m in members]
        assert "docs/api/endpoints.md" in names
        assert "docs/guides/setup.md" in names
        assert "docs/api/new_endpoints.md" not in names
        assert "docs/readme.md" not in names

        archived_files = {}
        for member in members:
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and ".." not in path.parts
            if member.isdir():
                continue
            assert member.isfile(), f"Unexpected non-file archive member: {member.name}"
            assert member.name not in archived_files, f"Duplicate archive member: {member.name}"
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived_files[member.name] = extracted.read()

        assert set(archived_files) == set(expected_report), "Archive contains missing or extra files."
        assert archived_files == expected_files, "Archived files are not exact transformations of the originals."

        content = archived_files["docs/api/endpoints.md"].decode("utf-8")
        assert "Status: Deprecated" in content
        assert "Status: Active" not in content
        assert "https://api.new.local/v2/users" in content
        assert "http://api.old.local/v1/" not in content

        content2 = archived_files["docs/guides/setup.md"].decode("utf-8")
        assert "Status: Deprecated" in content2
        assert "https://api.new.local/v2/downloads" in content2


def test_http_server_running():
    expected_data, _ = derive_expected()
    for i in range(3):
        try:
            with urllib.request.urlopen(SERVER_URL, timeout=2) as response:
                assert response.status == 200
                report_data = json.loads(response.read().decode("utf-8"))
                assert report_data == expected_data
                assert report_data == {"docs/api/endpoints.md": 2, "docs/guides/setup.md": 1}
            return
        except (urllib.error.URLError, ConnectionResetError, json.JSONDecodeError) as exc:
            if i == 2:
                pytest.fail(f"Failed to connect to server at {SERVER_URL} or invalid response: {exc}")
            time.sleep(1)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
