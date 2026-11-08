#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import os
import shutil
import stat
import subprocess
import time
import zipfile

import pytest

DATASET = "/home/user/dataset"
ORACLE = "/app/dataset_verifier"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


@pytest.fixture(scope="session")
def expected_outputs():
    assert os.path.isfile(ORACLE), f"Missing proprietary verifier: {ORACLE}"
    assert os.access(ORACLE, os.X_OK), f"Proprietary verifier is not executable: {ORACLE}"

    files = []
    seen = set()
    for root, dirs, names in os.walk(DATASET, followlinks=False):
        dirs.sort()
        names.sort()
        for name in names:
            path = os.path.abspath(os.path.join(root, name))
            st = os.stat(path, follow_symlinks=True)
            if not stat.S_ISREG(st.st_mode):
                continue
            identity = (st.st_dev, st.st_ino)
            if identity in seen:
                continue
            seen.add(identity)
            files.append(path)

    assert len(files) == 10000, f"Dataset should contain 10000 unique regular files, found {len(files)}"

    expected = []
    for path in files:
        result = subprocess.run(
            [ORACLE, path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
        if result.returncode == 0:
            digest = sha256_file(path)
            expected.append((path, digest + ".elf"))

    assert len(expected) == 500, f"Proprietary verifier should identify 500 valid files, found {len(expected)}"
    return expected


def test_process_dataset_exists_and_executable():
    bin_path = "/home/user/process_dataset"
    assert os.path.exists(bin_path), f"The compiled binary {bin_path} does not exist."
    assert os.path.isfile(bin_path), f"{bin_path} is not a file."

    st = os.stat(bin_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The binary {bin_path} is not executable."
    assert not os.path.islink(bin_path), f"{bin_path} must be a compiled executable, not a symlink."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not an ELF executable."


def test_process_dataset_performance_and_success(expected_outputs):
    bin_path = "/home/user/process_dataset"

    # We remove the output files if they exist from previous runs
    for f in ["/home/user/manifest.csv", "/home/user/clean_dataset.zip"]:
        if os.path.exists(f):
            os.remove(f)

    clean_dir = "/home/user/clean"
    if os.path.lexists(clean_dir):
        if os.path.isdir(clean_dir) and not os.path.islink(clean_dir):
            shutil.rmtree(clean_dir)
        else:
            os.remove(clean_dir)
    os.mkdir(clean_dir)

    start = time.time()
    result = subprocess.run([bin_path], capture_output=True, timeout=10)
    end = time.time()

    runtime = end - start

    assert result.returncode == 0, f"process_dataset failed with exit code {result.returncode}. Stderr: {result.stderr.decode('utf-8', errors='replace')}"
    assert runtime <= 1.5, f"Execution time {runtime:.2f}s exceeded the 1.5s threshold."


def test_outputs_generated_correctly(expected_outputs):
    manifest_path = "/home/user/manifest.csv"
    zip_path = "/home/user/clean_dataset.zip"
    clean_dir = "/home/user/clean"

    assert os.path.exists(manifest_path), f"Manifest file {manifest_path} was not generated."
    assert os.path.exists(zip_path), f"Zip archive {zip_path} was not generated."
    assert os.path.isdir(clean_dir), f"Clean directory {clean_dir} does not exist."
    assert os.path.isfile(manifest_path) and not os.path.islink(manifest_path)
    assert os.path.isfile(zip_path) and not os.path.islink(zip_path)

    with open(manifest_path, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) > 0, "Manifest file is empty, expected valid research data files to be found."

    # Check that zip is valid and contains files
    assert zipfile.is_zipfile(zip_path), f"{zip_path} is not a valid zip file."
    with zipfile.ZipFile(zip_path, "r") as z:
        zip_names = z.namelist()
        assert len(zip_names) > 0, "Zip archive is empty."

        # Verify that the manifest entries correspond to files in the zip
        for line in lines:
            if not line.strip():
                continue
            parts = line.split(",")
            assert len(parts) == 2, f"Invalid manifest line format: {line}"
            original_path, sha_name = parts[0].strip(), parts[1].strip()

            # The zip might contain the clean/ prefix or just the files, but the sha_name should be present
            found_in_zip = any(sha_name in z_name for z_name in zip_names)
            assert found_in_zip, f"File {sha_name} from manifest not found in the zip archive."

        assert z.testzip() is None, "Zip archive failed its integrity check."

        parsed = []
        for line in lines:
            parts = line.split(",")
            assert len(parts) == 2, f"Invalid manifest line format: {line}"
            original_path, sha_name = (part.strip() for part in parts)
            assert os.path.isabs(original_path), f"Manifest path is not absolute: {original_path}"
            assert original_path.startswith(DATASET + os.sep), f"Manifest path is outside the dataset: {original_path}"
            parsed.append((original_path, sha_name))

        assert collections.Counter(parsed) == collections.Counter(expected_outputs), \
            "Manifest does not list each and only the 500 oracle-approved files with the correct SHA256 name"

        expected_names = {name for _, name in expected_outputs}
        clean_entries = os.listdir(clean_dir)
        assert set(clean_entries) == expected_names, "Clean directory has missing, extra, or incorrectly named files"
        for name in clean_entries:
            path = os.path.join(clean_dir, name)
            assert os.path.isfile(path) and not os.path.islink(path), f"Invalid clean entry: {path}"
            assert sha256_file(path) + ".elf" == name, f"Clean file content does not match its SHA256 name: {name}"

        archive_files = [info for info in z.infolist() if not info.is_dir()]
        assert len(archive_files) == len(expected_names), "Zip has missing, duplicate, or extra files"
        assert {os.path.basename(info.filename.rstrip("/")) for info in archive_files} == expected_names, \
            "Zip filenames do not exactly match the expected clean files"
        for info in archive_files:
            name = os.path.basename(info.filename.rstrip("/"))
            assert hashlib.sha256(z.read(info)).hexdigest() + ".elf" == name, \
                f"Archived content does not match its SHA256 filename: {info.filename}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
