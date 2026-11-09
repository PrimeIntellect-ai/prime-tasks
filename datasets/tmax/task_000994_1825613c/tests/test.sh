#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import bz2
import gzip
import hashlib
import io
import os
import tarfile
import zipfile
import pytest

CURATED_DIR = "/home/user/curated"
MANIFEST_PATH = "/home/user/manifest.txt"
TARBALL_PATH = "/home/user/curated_artifacts.tar.gz"
RELEASE_BATCH = "/home/user/incoming/release_batch.tar"

EXPECTED_FILES = {
    "core_engine.bin",
    "libhelper.so",
    "plugin.bin",
    "libnet.so"
}


def derive_expected_artifacts():
    """Read and validate the nested archives in the supplied release batch."""
    artifacts = {}

    with tarfile.open(RELEASE_BATCH, "r:") as outer:
        for member in outer.getmembers():
            if not member.isfile():
                continue

            name = member.name.lower()
            if not name.endswith((".tar.gz", ".tar.bz2", ".zip")):
                continue

            source = outer.extractfile(member)
            assert source is not None
            archive_bytes = source.read()

            try:
                if name.endswith(".zip"):
                    with zipfile.ZipFile(io.BytesIO(archive_bytes), "r") as nested:
                        if nested.testzip() is not None:
                            continue
                        entries = [(info.filename, nested.read(info))
                                   for info in nested.infolist() if not info.is_dir()]
                else:
                    # Decompress the entire stream first so CRC/truncation errors are
                    # detected rather than accepting a tar reader that stops at EOF.
                    if name.endswith(".tar.gz"):
                        tar_bytes = gzip.decompress(archive_bytes)
                    else:
                        tar_bytes = bz2.decompress(archive_bytes)

                    entries = []
                    with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:") as nested:
                        for nested_member in nested.getmembers():
                            if nested_member.isfile():
                                extracted = nested.extractfile(nested_member)
                                assert extracted is not None
                                entries.append((nested_member.name, extracted.read()))
            except (OSError, EOFError, tarfile.TarError, zipfile.BadZipFile, RuntimeError):
                # Corrupt nested archives are intentionally ignored.
                continue

            for path, data in entries:
                basename = os.path.basename(path)
                if basename.endswith((".bin", ".so")):
                    assert basename not in artifacts, f"Duplicate artifact basename: {basename}"
                    artifacts[basename] = data

    return artifacts


SOURCE_ARTIFACTS = derive_expected_artifacts()


def test_curated_directory_contents():
    """Test that the curated directory contains exactly the expected valid binary artifacts."""
    assert os.path.isdir(CURATED_DIR), f"Directory {CURATED_DIR} does not exist."
    files = set(os.listdir(CURATED_DIR))
    assert files == EXPECTED_FILES, f"Expected files in {CURATED_DIR} to be {EXPECTED_FILES}, but got {files}."


def test_curated_files_match_release_batch():
    """Verify curated files are the actual bytes from valid nested archives."""
    assert set(SOURCE_ARTIFACTS) == EXPECTED_FILES, (
        f"Valid release archives yielded {set(SOURCE_ARTIFACTS)}, expected {EXPECTED_FILES}."
    )
    for filename in sorted(EXPECTED_FILES):
        filepath = os.path.join(CURATED_DIR, filename)
        assert os.path.isfile(filepath), f"File {filepath} is missing."
        assert not os.path.islink(filepath), f"File {filepath} must be a copied regular file."
        with open(filepath, "rb") as f:
            actual = f.read()
        assert actual == SOURCE_ARTIFACTS[filename], (
            f"Curated file {filename} does not match the artifact in release_batch.tar."
        )


def test_manifest_file():
    """Test that the manifest file exists and contains the correct SHA256 checksums."""
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."

    expected_lines = []
    for filename in sorted(EXPECTED_FILES):
        filepath = os.path.join(CURATED_DIR, filename)
        assert os.path.isfile(filepath), f"File {filepath} is missing, cannot compute checksum."
        with open(filepath, "rb") as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()
        expected_lines.append(f"{file_hash}  {filename}")

    expected_manifest = "\n".join(expected_lines)

    with open(MANIFEST_PATH, "r") as f:
        actual_manifest = f.read().strip()

    assert actual_manifest == expected_manifest, "Manifest contents do not match expected output (sorted by filename, with correct format)."


def test_curated_artifacts_tarball():
    """Test that the final tarball is gzip-compressed and contains the real curated artifacts."""
    assert os.path.isfile(TARBALL_PATH), f"Tarball {TARBALL_PATH} does not exist."
    assert tarfile.is_tarfile(TARBALL_PATH), f"File {TARBALL_PATH} is not a valid tar archive."

    try:
        with tarfile.open(TARBALL_PATH, "r:gz") as tar:
            names = tar.getnames()
            expected_tar_files = {f"curated/{f}" for f in EXPECTED_FILES}
            actual_files = {name.lstrip("./") for name in names}

            for ef in expected_tar_files:
                assert ef in actual_files, f"Expected file {ef} missing from tarball {TARBALL_PATH}."

            for filename in sorted(EXPECTED_FILES):
                normalized = f"curated/{filename}"
                matches = [m for m in tar.getmembers() if m.name.lstrip("./") == normalized]
                assert len(matches) == 1, f"Expected exactly one tar member for {normalized}."
                member = matches[0]
                assert member.isfile(), f"Tar member {normalized} is not a regular file."
                extracted = tar.extractfile(member)
                assert extracted is not None
                assert extracted.read() == SOURCE_ARTIFACTS[filename], (
                    f"Tar member {normalized} does not match the source artifact."
                )
    except tarfile.ReadError:
        pytest.fail(f"Tarball {TARBALL_PATH} could not be read as a gzip-compressed tar archive.")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
