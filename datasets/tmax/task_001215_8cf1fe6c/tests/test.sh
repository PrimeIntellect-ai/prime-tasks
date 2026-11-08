#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile
import subprocess
import shutil
from pathlib import PurePosixPath
import pytest

EXPECTED_ARCHIVED = {
    "some-other-file.bdat": b"dummy\n",
    "nested/archived-alpha-file 3.bdat": b"dummy\n",
}

EXPECTED_CURATED = {
    "archived-alpha-file1.txt": b"dummy\n",
    "stable-v2-file2.txt": b"dummy\n",
    "nested/stable-v2-file4.manifest": (
        b"Content with archived-alpha- prefix\n"
        b"Content with stable-v2- prefix\n"
    ),
    "nested/normal.manifest": (
        b"Content with archived-alpha- prefix\n"
        b"Content with stable-v2- prefix\n"
    ),
}


def read_archive_files(path, mode, optional_root):
    with tarfile.open(path, mode) as tar:
        members = tar.getmembers()
        for member in members:
            assert member.isdir() or member.isfile(), (
                f"Unexpected non-regular archive member: {member.name}"
            )

        file_members = [member for member in members if member.isfile()]
        cleaned_names = []
        for member in file_members:
            assert not member.name.startswith("/"), f"Absolute archive path: {member.name}"
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            parts = PurePosixPath(name).parts
            assert name and ".." not in parts, f"Unsafe archive path: {member.name}"
            cleaned_names.append(name)

        prefix = optional_root + "/"
        if cleaned_names and all(name.startswith(prefix) for name in cleaned_names):
            cleaned_names = [name[len(prefix):] for name in cleaned_names]

        result = {}
        for member, name in zip(file_members, cleaned_names):
            assert name not in result, f"Duplicate archive path: {name}"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive member: {member.name}"
            result[name] = extracted.read()
        return result


def test_curation_accuracy():
    assert os.path.exists("/app/archived.tar"), "Missing /app/archived.tar"
    assert os.path.exists("/app/curated_repo.tar.xz"), "Missing /app/curated_repo.tar.xz"

    correct = 0
    total = 0

    # Check archived.tar
    with tarfile.open("/app/archived.tar", "r") as tar:
        for member in tar.getmembers():
            if member.isfile():
                total += 1
                if member.name.endswith(".bdat"):
                    correct += 1

    # Check curated_repo.tar.xz
    extract_dir = "/tmp/eval_repo_extract"
    if os.path.exists(extract_dir):
        shutil.rmtree(extract_dir)
    os.makedirs(extract_dir, exist_ok=True)

    try:
        subprocess.run(["tar", "-xf", "/app/curated_repo.tar.xz", "-C", extract_dir], check=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to extract /app/curated_repo.tar.xz")

    for root, dirs, files in os.walk(extract_dir):
        for f in files:
            total += 1
            if "legacy-v1-" not in f and "beta-v2-" not in f and not f.endswith(".bdat"):
                correct += 1
            if f.endswith(".manifest"):
                with open(os.path.join(root, f), "r", errors="ignore") as mf:
                    lines = mf.readlines()
                    total += 1
                    # Check header stripped and text replaced
                    if len(lines) > 0 and "legacy-v1-" not in "".join(lines):
                        correct += 1

    accuracy = correct / total if total > 0 else 0

    shutil.rmtree(extract_dir, ignore_errors=True)

    assert accuracy >= 0.98, f"Curation Accuracy Ratio {accuracy:.4f} is below threshold 0.98"

    # Completeness and content checks against the repository supplied by setup.
    # Permit the conventional optional top-level directory in each tarball, but
    # require every expected relative path and reject missing or extra files.
    archived_files = read_archive_files("/app/archived.tar", "r:", "archived")
    curated_files = read_archive_files("/app/curated_repo.tar.xz", "r:xz", "repo")

    assert archived_files == EXPECTED_ARCHIVED, (
        f"Archived repository mismatch: expected {sorted(EXPECTED_ARCHIVED)}, "
        f"got {sorted(archived_files)}"
    )
    assert curated_files == EXPECTED_CURATED, (
        f"Curated repository mismatch: expected {sorted(EXPECTED_CURATED)}, "
        f"got {sorted(curated_files)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
