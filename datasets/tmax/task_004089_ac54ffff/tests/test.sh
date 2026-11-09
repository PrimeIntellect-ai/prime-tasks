#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tarfile
from pathlib import PurePosixPath

import pytest

SCRIPT = "/home/user/organize.py"
SOURCE = "/app/messy_project"
ORGANIZED = "/home/user/organized_project"
MANIFEST = os.path.join(ORGANIZED, "manifest.json")
TARBALL = "/home/user/project.tar.gz"
EXPECTED_PATHS = {
    "media/images/photo.jpg",
    "docs/notes.md",
    "src/script.py",
    "logs/app.json",
}


def remove_path(path):
    if os.path.lexists(path):
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)
        else:
            shutil.rmtree(path)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def calculate_f1(pred_manifest_path, true_manifest):
    try:
        with open(pred_manifest_path, "r", encoding="utf-8") as f:
            pred = json.load(f)
        if not isinstance(pred, dict):
            return 0.0
        pred_set = set(pred.items())
    except Exception:
        return 0.0

    true_set = set(true_manifest.items())
    tp = len(pred_set.intersection(true_set))
    fp = len(pred_set - true_set)
    fn = len(true_set - pred_set)

    if tp == 0:
        return 0.0
    precision = tp / (tp + fp)
    recall = tp / (tp + fn)
    return 2 * (precision * recall) / (precision + recall)


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT), f"Python script missing at {SCRIPT}"
    assert not os.path.islink(SCRIPT), f"Python script must not be a symlink: {SCRIPT}"

    # Restore the original input so the submitted artifact itself is exercised.
    remove_path(SOURCE)
    remove_path(ORGANIZED)
    remove_path(TARBALL)
    os.makedirs(SOURCE, mode=0o777)
    os.chmod(SOURCE, 0o777)

    fixtures = {
        "script.py": b"",
        "notes.md": b"",
        "photo.jpg": b"",
        "app.txt": b"[2023-01-01 12:00:00] Error occurred\n",
    }
    for name, contents in fixtures.items():
        path = os.path.join(SOURCE, name)
        with open(path, "wb") as f:
            f.write(contents)
        os.chmod(path, 0o666)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"organize.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_project_tarball_exists():
    tarball_path = TARBALL
    assert os.path.isfile(tarball_path), f"Tarball missing at {tarball_path}"
    assert stat.S_ISREG(os.lstat(tarball_path).st_mode), "Tarball must be a regular file"

    with open(tarball_path, "rb") as f:
        assert f.read(2) == b"\x1f\x8b", "project.tar.gz is not gzip-compressed"

    archived_files = {}
    with tarfile.open(tarball_path, mode="r:gz") as archive:
        for member in archive.getmembers():
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and ".." not in path.parts, "Unsafe archive path"
            assert not member.issym() and not member.islnk(), "Archive must not contain links"
            if not member.isfile():
                continue

            parts = tuple(part for part in path.parts if part not in ("", "."))
            if "organized_project" in parts:
                index = parts.index("organized_project")
                relative = "/".join(parts[index + 1:])
            else:
                relative = "/".join(parts)

            assert relative and relative not in archived_files, "Duplicate archive member"
            extracted = archive.extractfile(member)
            assert extracted is not None
            archived_files[relative] = extracted.read()

    expected_archive_files = EXPECTED_PATHS | {"manifest.json"}
    assert set(archived_files) == expected_archive_files, (
        f"Archive members differ: {set(archived_files)}"
    )
    for relative, archived_content in archived_files.items():
        with open(os.path.join(ORGANIZED, *relative.split("/")), "rb") as f:
            assert archived_content == f.read(), f"Archived content differs for {relative}"


def test_manifest_f1_score():
    manifest_path = MANIFEST
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"
    assert not os.path.islink(manifest_path), "Manifest must not be a symlink"

    actual_files = set()
    for root, dirs, files in os.walk(ORGANIZED):
        for name in files:
            full_path = os.path.join(root, name)
            relative = os.path.relpath(full_path, ORGANIZED).replace(os.sep, "/")
            if relative != "manifest.json":
                actual_files.add(relative)
                assert os.path.isfile(full_path) and not os.path.islink(full_path)
    assert actual_files == EXPECTED_PATHS, f"Incorrect organized files: {actual_files}"

    for relative in ("media/images/photo.jpg", "docs/notes.md", "src/script.py"):
        with open(os.path.join(ORGANIZED, *relative.split("/")), "rb") as f:
            assert f.read() == b"", f"Unexpected content in {relative}"

    log_path = os.path.join(ORGANIZED, "logs", "app.json")
    with open(log_path, "r", encoding="utf-8") as f:
        log_data = json.load(f)
    assert log_data == {
        "time": "2023-01-01 12:00:00",
        "msg": "Error occurred",
    }, f"Incorrect converted log: {log_data!r}"

    true_manifest = {
        relative: sha256_file(os.path.join(ORGANIZED, *relative.split("/")))
        for relative in EXPECTED_PATHS
    }

    with open(manifest_path, "r", encoding="utf-8") as f:
        pred = json.load(f)
    assert isinstance(pred, dict), "Manifest must be a JSON object"
    assert set(pred) == EXPECTED_PATHS, f"Incorrect manifest paths: {set(pred)}"
    for relative, checksum in pred.items():
        assert isinstance(checksum, str), f"Checksum for {relative} must be a string"
        assert checksum == true_manifest[relative], f"Incorrect checksum for {relative}"

    f1 = calculate_f1(manifest_path, true_manifest)
    assert f1 >= 0.95, (
        f"F1 score of manifest paths and checksums is {f1:.4f}, "
        "which is below the threshold of 0.95"
    )

    for original in ("script.py", "notes.md", "photo.jpg", "app.txt"):
        assert not os.path.exists(os.path.join(SOURCE, original)), (
            f"Source file was not moved: {original}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
