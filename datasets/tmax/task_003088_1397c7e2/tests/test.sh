#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import hashlib
import os
import shutil
import stat
import subprocess
import tempfile

import pytest

RAW = "/home/user/raw_artifacts"
CURATED = "/home/user/curated"
SCRIPT = "/home/user/curate_artifacts.sh"
PACKER = "/app/artifact_packer"
ARCHIVE = "/home/user/final_archive.pack"

A_FILES = [f"file_A_{i}.bin" for i in range(1, 6)]
B_FILES = [f"file_B_{i}.bin" for i in range(1, 6)]
D_FILES = [f"doc_D_{i}.doc" for i in range(1, 6)]
C_GZ_FILES = [f"meta_C_{i}.meta.gz" for i in range(1, 6)]
EXPECTED_RAW = set(A_FILES + B_FILES + D_FILES + C_GZ_FILES)


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def test_script_exists_and_executes_packer():
    assert os.path.isfile(SCRIPT) and not os.path.islink(SCRIPT), \
        f"Required Bash script {SCRIPT} is missing or is not a regular file."
    assert os.path.isfile(PACKER), f"Packer {PACKER} is missing."

    shutil.rmtree(CURATED, ignore_errors=True)
    try:
        os.unlink(ARCHIVE)
    except FileNotFoundError:
        pass

    fd, saved_packer = tempfile.mkstemp(prefix="artifact_packer.saved.", dir="/tmp")
    os.close(fd)
    os.unlink(saved_packer)
    marker = tempfile.mktemp(prefix="artifact_packer.called.", dir="/tmp")

    os.replace(PACKER, saved_packer)
    wrapper = f'''#!/bin/bash
printf '%s\\n%s\\n' "$1" "$2" > {marker!r}
exec {saved_packer!r} "$@"
'''
    with open(PACKER, "w") as f:
        f.write(wrapper)
    os.chmod(PACKER, 0o755)

    try:
        result = subprocess.run(
            ["/bin/bash", SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=120,
        )
    finally:
        try:
            os.unlink(PACKER)
        except FileNotFoundError:
            pass
        os.replace(saved_packer, PACKER)

    assert result.returncode == 0, \
        f"{SCRIPT} failed when executed with Bash:\n{result.stdout}"
    assert os.path.isfile(marker), \
        f"{SCRIPT} did not execute {PACKER}."
    with open(marker) as f:
        args = f.read().splitlines()
    assert args == [CURATED, ARCHIVE], \
        f"Packer was called with incorrect arguments: {args}"


def test_raw_artifact_completeness_and_contents():
    assert os.path.isdir(RAW), f"Raw artifact directory {RAW} is missing."
    actual = set(os.listdir(RAW))
    assert actual == EXPECTED_RAW, \
        f"Unexpected raw artifact set. Missing: {sorted(EXPECTED_RAW-actual)}; extra: {sorted(actual-EXPECTED_RAW)}"

    for name in EXPECTED_RAW:
        path = os.path.join(RAW, name)
        assert os.path.isfile(path) and not os.path.islink(path), \
            f"Raw artifact {path} must be a regular file."

    assert all(os.path.getsize(os.path.join(RAW, n)) == 1024 * 1024 for n in A_FILES)
    assert all(os.path.getsize(os.path.join(RAW, n)) == 500 * 1024 for n in B_FILES)
    assert all(os.path.getsize(os.path.join(RAW, n)) == 200000 for n in D_FILES)

    a_hashes = {digest(os.path.join(RAW, n)) for n in A_FILES}
    b_hashes = {digest(os.path.join(RAW, n)) for n in B_FILES}
    d_hashes = {digest(os.path.join(RAW, n)) for n in D_FILES}
    assert len(a_hashes) == len(b_hashes) == len(d_hashes) == 1, \
        "Files in each original duplicate group must retain identical contents."
    assert len(a_hashes | b_hashes | d_hashes) == 3, \
        "Distinct original content groups were overwritten or conflated."

    doc_content = open(os.path.join(RAW, D_FILES[0]), "rb").read()
    for name in C_GZ_FILES:
        try:
            with gzip.open(os.path.join(RAW, name), "rb") as gz:
                content = gz.read()
        except Exception as e:
            pytest.fail(f"File {name} is not a valid gzip file: {e}")
        assert content == doc_content, \
            f"{name} does not decompress to the original metadata content."


def test_deduplication_hard_links():
    """Check that identical files in raw_artifacts have been hard-linked."""
    inodes_a = {os.stat(os.path.join(RAW, f)).st_ino for f in A_FILES}
    inodes_b = {os.stat(os.path.join(RAW, f)).st_ino for f in B_FILES}
    inodes_d = {os.stat(os.path.join(RAW, f)).st_ino for f in D_FILES}

    assert len(inodes_a) == 1, f"Expected 1 unique inode for file_A_*, found {len(inodes_a)}. Hard linking incomplete."
    assert len(inodes_b) == 1, f"Expected 1 unique inode for file_B_*, found {len(inodes_b)}. Hard linking incomplete."
    assert len(inodes_d) == 1, f"Expected 1 unique inode for doc_D_*, found {len(inodes_d)}. Hard linking incomplete."


def test_metadata_compression():
    """Check that .meta.txt files are compressed to .meta.gz and originals removed."""
    meta_txt_files = [f for f in os.listdir(RAW) if f.endswith(".meta.txt")]
    assert len(meta_txt_files) == 0, f"Found uncompressed .meta.txt files: {meta_txt_files}. They should be removed."

    meta_gz_files = [f for f in os.listdir(RAW) if f.endswith(".meta.gz")]
    assert len(meta_gz_files) > 0, "No .meta.gz files found in raw_artifacts."
    assert set(meta_gz_files) == set(C_GZ_FILES), "Metadata files are missing or incorrectly named."

    inodes_c = set()
    for f in meta_gz_files:
        path = os.path.join(RAW, f)
        inodes_c.add(os.stat(path).st_ino)
        try:
            with gzip.open(path, "rb") as gz:
                gz.read()
        except Exception as e:
            pytest.fail(f"File {f} is not a valid gzip file: {e}")

    assert len(inodes_c) == 1, f"Expected 1 unique inode for meta_C_*.meta.gz, found {len(inodes_c)}. Hard linking incomplete."


def test_staging_directory_structure_and_symlinks():
    """Check that curated directory has correct structure and complete symlinks."""
    expected = {
        "binaries": A_FILES + B_FILES,
        "docs": D_FILES,
        "metadata": C_GZ_FILES,
    }

    assert os.path.isdir(CURATED) and not os.path.islink(CURATED)
    assert set(os.listdir(CURATED)) == set(expected), \
        "Curated must contain exactly binaries, docs, and metadata."

    for subdir, names in expected.items():
        directory = os.path.join(CURATED, subdir)
        assert os.path.isdir(directory) and not os.path.islink(directory), \
            f"Directory {directory} is missing or invalid."
        assert set(os.listdir(directory)) == set(names), \
            f"{directory} does not contain exactly the required files."
        for name in names:
            path = os.path.join(directory, name)
            assert os.path.islink(path), f"{path} is not a symlink."
            assert os.path.exists(path), f"{path} is a broken symlink."
            expected_target = os.path.join(RAW, name)
            assert os.path.realpath(path) == expected_target, \
                f"{path} does not point to {expected_target}."

    for f in os.listdir(os.path.join(CURATED, "binaries")):
        assert f.endswith(".bin"), f"Found non-binary file {f} in binaries directory."
    for f in os.listdir(os.path.join(CURATED, "docs")):
        assert f.endswith(".doc"), f"Found non-doc file {f} in docs directory."
    for f in os.listdir(os.path.join(CURATED, "metadata")):
        assert f.endswith(".meta.gz"), f"Found non-meta.gz file {f} in metadata directory."


def test_final_archive_size_metric_and_contents():
    """Check that the final archive was produced by the packer and meets the stated limit."""
    assert os.path.isfile(ARCHIVE), f"Final archive {ARCHIVE} is missing."

    fd, expected_archive = tempfile.mkstemp(prefix="expected_archive.", dir="/tmp")
    os.close(fd)
    try:
        subprocess.run([PACKER, CURATED, expected_archive], check=True, timeout=120)
        with open(ARCHIVE, "rb") as actual, open(expected_archive, "rb") as expected:
            assert actual.read() == expected.read(), \
                "Final archive contents do not match artifact_packer output for curated/."
    finally:
        try:
            os.unlink(expected_archive)
        except FileNotFoundError:
            pass

    size = os.path.getsize(ARCHIVE)
    threshold = 1500000
    assert size <= threshold, f"Archive size is {size} bytes, which exceeds the threshold of {threshold} bytes."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
