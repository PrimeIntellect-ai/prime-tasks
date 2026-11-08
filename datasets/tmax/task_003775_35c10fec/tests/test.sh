#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import json
import hashlib
import pathlib
import secrets
import shutil
import subprocess
import tarfile
import zipfile
import pytest

UPLOADS_DIR = "/home/user/uploads"
PROCESSED_DIR = "/home/user/processed"
EXTRACTED_DIR = os.path.join(PROCESSED_DIR, "extracted")
DELETED_LOG = os.path.join(PROCESSED_DIR, "deleted.log")
MANIFEST_FILE = os.path.join(PROCESSED_DIR, "manifest.json")


def _capture_candidate_scripts():
    candidates = []
    excluded = {
        "/tmp/setup.py",
        "/tmp/test_final_state.py",
    }
    for root in ("/home/user", "/root", "/tmp"):
        if not os.path.isdir(root):
            continue
        for directory, dirnames, filenames in os.walk(root):
            dirnames[:] = [
                name for name in dirnames
                if name not in {".cache", "__pycache__", ".git", "site-packages", "dist-packages"}
            ]
            for filename in filenames:
                if not filename.endswith(".py"):
                    continue
                path = os.path.abspath(os.path.join(directory, filename))
                if path in excluded:
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    data = pathlib.Path(path).read_bytes()
                except OSError:
                    continue

                # All scripts in the user's home are candidates. Outside it,
                # avoid unrelated system scripts unless they appear relevant.
                if path.startswith("/home/user/") or (
                    b"zipfile" in data and b"tarfile" in data and b"uploads" in data
                ):
                    candidates.append((path, data))
    return candidates


# Capture scripts before the behavioral test replaces the output directories.
CANDIDATE_SCRIPTS = _capture_candidate_scripts()


def test_deleted_log_contents():
    assert os.path.isfile(DELETED_LOG), f"Missing deleted log file: {DELETED_LOG}"
    with open(DELETED_LOG, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["bad_actor.tar.gz", "mixed.zip"]
    assert lines == expected_lines, f"Expected {DELETED_LOG} to contain exactly {expected_lines} in alphabetical order, but got {lines}"


def test_malicious_archives_deleted():
    for filename in ["bad_actor.tar.gz", "mixed.zip"]:
        path = os.path.join(UPLOADS_DIR, filename)
        assert not os.path.exists(path), f"Malicious archive {path} was not deleted from uploads directory."


def test_safe_archives_exist():
    for filename in ["safe_data.zip", "safe_archive.tar.gz"]:
        path = os.path.join(UPLOADS_DIR, filename)
        assert os.path.isfile(path), f"Safe archive {path} should not have been deleted."


def test_extracted_files_content_and_encoding():
    assert os.path.isdir(EXTRACTED_DIR), f"Missing extracted directory: {EXTRACTED_DIR}"

    notes_path = os.path.join(EXTRACTED_DIR, "notes.txt")
    assert os.path.isfile(notes_path), f"Missing extracted file: {notes_path}"
    with open(notes_path, "rb") as f:
        notes_content = f.read()
    assert notes_content == "München".encode("utf-8"), f"notes.txt was not correctly converted to UTF-8. Got {notes_content!r}"

    report_path = os.path.join(EXTRACTED_DIR, "docs", "report.txt")
    assert os.path.isfile(report_path), f"Missing extracted file: {report_path}"
    with open(report_path, "rb") as f:
        report_content = f.read()
    assert report_content == "Voilà".encode("utf-8"), f"docs/report.txt was not correctly converted to UTF-8. Got {report_content!r}"

    stats_path = os.path.join(EXTRACTED_DIR, "data", "stats.bin")
    assert os.path.isfile(stats_path), f"Missing extracted file: {stats_path}"
    with open(stats_path, "rb") as f:
        stats_content = f.read()
    assert stats_content == b'\x00\x01\x02\x03', f"data/stats.bin was improperly modified. Got {stats_content!r}"


def test_manifest_json():
    assert os.path.isfile(MANIFEST_FILE), f"Missing manifest file: {MANIFEST_FILE}"
    with open(MANIFEST_FILE, "r", encoding="utf-8") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {MANIFEST_FILE} is not valid JSON.")

    expected_manifest = {
        "notes.txt": hashlib.sha256("München".encode("utf-8")).hexdigest(),
        "data/stats.bin": hashlib.sha256(b'\x00\x01\x02\x03').hexdigest(),
        "docs/report.txt": hashlib.sha256("Voilà".encode("utf-8")).hexdigest()
    }

    assert manifest == expected_manifest, f"Manifest content does not match expected output. Got: {manifest}"


def test_malicious_members_were_not_extracted():
    assert not os.path.exists("/home/user/escaped.txt"), "Traversal member escaped the extraction directory"
    assert not os.path.exists(os.path.join(EXTRACTED_DIR, "good.bin")), "A file from malicious mixed.zip was extracted"
    with open("/etc/passwd", "rb") as f:
        assert f.read() != b"fake passwd data", "Absolute/traversal member overwrote /etc/passwd"


def _add_tar_bytes(tf, name, data):
    info = tarfile.TarInfo(name=name)
    info.size = len(data)
    tf.addfile(info, io.BytesIO(data))


def _prepare_random_fixture(token):
    shutil.rmtree(UPLOADS_DIR, ignore_errors=True)
    shutil.rmtree(PROCESSED_DIR, ignore_errors=True)
    os.makedirs(UPLOADS_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)

    safe_zip = f"safe_{token}.zip"
    safe_tar = f"safe_{token}.tar.gz"
    bad_abs = f"absolute_{token}.zip"
    bad_dotdot = f"traversal_{token}.tar.gz"
    bad_backslash = f"backslash_{token}.zip"

    text_one_path = f"customers/{token}/city.txt"
    text_two_path = f"reports/{token}.txt"
    binary_path = f"blobs/{token}.bin"
    text_one = f"Zürich-{token}"
    text_two = f"Crème brûlée-{token}"
    binary = secrets.token_bytes(37)

    with zipfile.ZipFile(os.path.join(UPLOADS_DIR, safe_zip), "w") as zf:
        zf.writestr(text_one_path, text_one.encode("cp1252"))
        zf.writestr(binary_path, binary)

    with tarfile.open(os.path.join(UPLOADS_DIR, safe_tar), "w:gz") as tf:
        _add_tar_bytes(tf, text_two_path, text_two.encode("cp1252"))

    with zipfile.ZipFile(os.path.join(UPLOADS_DIR, bad_abs), "w") as zf:
        zf.writestr(f"innocent-{token}.bin", b"must not be extracted")
        zf.writestr(f"/home/user/verifier-absolute-{token}", b"escaped")

    with tarfile.open(os.path.join(UPLOADS_DIR, bad_dotdot), "w:gz") as tf:
        _add_tar_bytes(tf, f"harmless-{token}.txt", b"must not be extracted")
        _add_tar_bytes(tf, f"../../../../home/user/verifier-traversal-{token}", b"escaped")

    with zipfile.ZipFile(os.path.join(UPLOADS_DIR, bad_backslash), "w") as zf:
        zf.writestr(f"ok-{token}.bin", b"must not be extracted")
        zf.writestr(f"folder\\..\\evil-{token}.txt", b"malicious")

    expected_manifest = {
        text_one_path: hashlib.sha256(text_one.encode("utf-8")).hexdigest(),
        binary_path: hashlib.sha256(binary).hexdigest(),
        text_two_path: hashlib.sha256(text_two.encode("utf-8")).hexdigest(),
    }
    return {
        "safe": [safe_zip, safe_tar],
        "bad": sorted([bad_abs, bad_dotdot, bad_backslash]),
        "manifest": expected_manifest,
        "binary_path": binary_path,
        "binary": binary,
        "forbidden_extracted": [
            f"innocent-{token}.bin",
            f"harmless-{token}.txt",
            f"ok-{token}.bin",
            f"folder\\..\\evil-{token}.txt",
        ],
        "canaries": [
            f"/home/user/verifier-absolute-{token}",
            f"/home/user/verifier-traversal-{token}",
        ],
    }


def _validate_random_result(expected):
    for filename in expected["safe"]:
        assert os.path.isfile(os.path.join(UPLOADS_DIR, filename)), f"Safe archive was deleted: {filename}"
    for filename in expected["bad"]:
        assert not os.path.exists(os.path.join(UPLOADS_DIR, filename)), f"Malicious archive remains: {filename}"

    with open(DELETED_LOG, "r", encoding="utf-8") as f:
        deleted = [line.strip() for line in f if line.strip()]
    assert deleted == expected["bad"], f"Incorrect randomized deleted.log: {deleted}"

    with open(MANIFEST_FILE, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    assert manifest == expected["manifest"], f"Incorrect randomized manifest: {manifest}"

    binary_file = os.path.join(EXTRACTED_DIR, *expected["binary_path"].split("/"))
    with open(binary_file, "rb") as f:
        assert f.read() == expected["binary"], "Random binary file was modified"

    for relative in expected["forbidden_extracted"]:
        assert not os.path.exists(os.path.join(EXTRACTED_DIR, relative)), f"File from malicious archive was extracted: {relative}"
    for canary in expected["canaries"]:
        assert not os.path.exists(canary), f"Archive member escaped extraction: {canary}"


def test_zz_reusable_script_on_random_archives():
    assert CANDIDATE_SCRIPTS, "No reusable Python script was found"
    failures = []

    for index, (original_path, source) in enumerate(CANDIDATE_SCRIPTS):
        token = secrets.token_hex(6)
        expected = _prepare_random_fixture(token)
        for canary in expected["canaries"]:
            try:
                os.remove(canary)
            except FileNotFoundError:
                pass

        candidate = f"/tmp/verifier_candidate_{index}.py"
        pathlib.Path(candidate).write_bytes(source)
        try:
            result = subprocess.run(
                ["python3", candidate],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
                check=False,
            )
            assert result.returncode == 0, (
                f"Script exited with {result.returncode}: "
                f"{result.stderr.decode('utf-8', errors='replace')}"
            )
            _validate_random_result(expected)
            return
        except Exception as exc:
            failures.append(f"{original_path}: {exc}")
        finally:
            try:
                os.remove(candidate)
            except FileNotFoundError:
                pass

    pytest.fail("No discovered Python script correctly processed randomized archives. " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
