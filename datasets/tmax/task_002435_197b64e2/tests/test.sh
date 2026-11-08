#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import posixpath
import re
import shutil
import stat
import subprocess
import tarfile

import pytest

SCRIPT = "/home/user/clean_dataset.sh"
RAW_ARCHIVE = "/home/user/raw_data.tar.gz"
EXTRACTED = "/home/user/extracted"
MERGED = "/home/user/merged.dat"
CLEANED = "/home/user/cleaned.dat"
CHUNKS = "/home/user/chunks"
PROCESSED = "/home/user/processed_dataset.tar.gz"
EXPECTED = {}


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def normalized_member_name(name):
    name = posixpath.normpath(name)
    while name.startswith("./"):
        name = name[2:]
    assert name not in ("", "."), f"Invalid empty archive member name: {name!r}"
    assert not name.startswith("/") and ".." not in name.split("/"), \
        f"Unsafe archive member name: {name!r}"
    return name.rstrip("/")


def derive_expected_from_input():
    dat_files = []
    with tarfile.open(RAW_ARCHIVE, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            relpath = normalized_member_name(member.name)
            if not relpath.endswith(".dat"):
                continue
            source = archive.extractfile(member)
            assert source is not None
            full_path = os.path.join(EXTRACTED, *relpath.split("/"))
            dat_files.append((full_path, source.read()))

    assert dat_files, "The input archive contains no regular .dat files."
    dat_files.sort(key=lambda item: item[0])
    merged = b"".join(data for _, data in dat_files)

    cleaned_lines = []
    for line in merged.splitlines(keepends=True):
        if line.startswith(b"ERROR") or line.startswith(b"DEBUG"):
            continue
        cleaned_lines.append(
            re.sub(rb"([0-9]{4})/([0-9]{2})/([0-9]{2})", rb"\1-\2-\3", line)
        )
    cleaned = b"".join(cleaned_lines)
    chunks = [b"".join(cleaned_lines[i:i + 50]) for i in range(0, len(cleaned_lines), 50)]

    return {
        "merged": merged,
        "cleaned": cleaned,
        "lines": cleaned_lines,
        "chunks": chunks,
    }


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    mode = os.stat(SCRIPT).st_mode
    assert bool(mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."
    assert os.path.isfile(RAW_ARCHIVE), f"Input archive {RAW_ARCHIVE} does not exist."

    EXPECTED.update(derive_expected_from_input())

    # Force the submitted script to perform the complete pipeline itself.
    for path in (EXTRACTED, MERGED, CLEANED, CHUNKS, PROCESSED):
        remove_path(path)

    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout.decode(errors='replace')}\n"
        f"stderr:\n{result.stderr.decode(errors='replace')}"
    )


def test_script_exists_and_executable():
    """Verify that the clean_dataset.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."


def test_intermediate_files_match_sorted_input_merge():
    """Verify the merge and transformation against data derived from the input archive."""
    assert os.path.isfile(MERGED), f"Merged file {MERGED} does not exist."
    assert os.path.isfile(CLEANED), f"Cleaned file {CLEANED} does not exist."
    with open(MERGED, "rb") as f:
        assert f.read() == EXPECTED["merged"], \
            "merged.dat is not the full-path-sorted concatenation of the input .dat files."
    with open(CLEANED, "rb") as f:
        assert f.read() == EXPECTED["cleaned"], \
            "cleaned.dat does not contain the required transformation of merged.dat."


def test_processed_archive_exists():
    """Verify that the final processed_dataset.tar.gz archive exists."""
    assert os.path.isfile(PROCESSED), f"Archive {PROCESSED} does not exist."


def test_processed_archive_contents_and_transformations():
    """Verify exact archive shape, chunk sizes, and contents."""
    assert os.path.isfile(PROCESSED), f"Archive {PROCESSED} does not exist."

    expected_files = ["chunk_aa.txt", "chunk_ab.txt", "chunk_ac.txt"]
    assert len(EXPECTED["lines"]) == 121
    assert [len(chunk.splitlines()) for chunk in EXPECTED["chunks"]] == [50, 50, 21]
    assert len(EXPECTED["chunks"]) == 3

    with tarfile.open(PROCESSED, "r:gz") as archive:
        members = archive.getmembers()
        names = [normalized_member_name(member.name) for member in members]
        assert len(names) == len(set(names)), "Archive contains duplicate member names."
        expected_names = {"chunks"} | {f"chunks/{name}" for name in expected_files}
        assert set(names) == expected_names, \
            f"Archive must contain only chunks/ and its expected files; found {sorted(names)}."

        by_name = dict(zip(names, members))
        assert by_name["chunks"].isdir(), "The chunks archive member is not a directory."

        all_lines = []
        for index, filename in enumerate(expected_files):
            member = by_name[f"chunks/{filename}"]
            assert member.isfile(), f"{filename} is not a regular file in the archive."
            source = archive.extractfile(member)
            assert source is not None
            data = source.read()
            assert data == EXPECTED["chunks"][index], \
                f"{filename} does not contain the expected transformed input lines."

            lines = data.splitlines(keepends=True)
            all_lines.extend(lines)
            required_size = 50 if filename != "chunk_ac.txt" else 21
            assert len(lines) == required_size, \
                f"{filename} should have exactly {required_size} lines, found {len(lines)}."

    assert len(all_lines) == 121, \
        f"Total lines across all chunks should be 121, found {len(all_lines)}."
    assert b"".join(all_lines) == EXPECTED["cleaned"]

    for i, line in enumerate(all_lines):
        assert not line.startswith(b"ERROR"), f"Line {i+1} starts with ERROR."
        assert not line.startswith(b"DEBUG"), f"Line {i+1} starts with DEBUG."
        assert b"2023/" not in line, f"Line {i+1} contains an unconverted date."
        assert b"2023-" in line, f"Line {i+1} does not contain a converted date."


def test_chunk_directory_matches_archive():
    """Verify the requested on-disk chunks were also created correctly."""
    assert os.path.isdir(CHUNKS) and not os.path.islink(CHUNKS), \
        f"Chunk directory {CHUNKS} does not exist as a real directory."
    expected_files = ["chunk_aa.txt", "chunk_ab.txt", "chunk_ac.txt"]
    assert sorted(os.listdir(CHUNKS)) == expected_files
    for index, filename in enumerate(expected_files):
        path = os.path.join(CHUNKS, filename)
        assert os.path.isfile(path) and not os.path.islink(path)
        with open(path, "rb") as f:
            assert f.read() == EXPECTED["chunks"][index]


def test_symlinks_removed():
    """Verify that extracted exists and all symlinks inside it were removed."""
    assert os.path.isdir(EXTRACTED) and not os.path.islink(EXTRACTED), \
        f"Extracted directory {EXTRACTED} does not exist as a real directory."
    for root, dirs, files in os.walk(EXTRACTED, followlinks=False):
        for name in dirs + files:
            path = os.path.join(root, name)
            assert not os.path.islink(path), \
                f"Symlink found at {path}, which should have been deleted."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
