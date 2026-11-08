#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import subprocess
import tarfile
import tempfile

DRAFTS_DIR = "/home/user/drafts"
TAR_FILE = "/home/user/release.tar.gz"
CPP_BIN = "/home/user/process_docs"
CPP_SOURCE = "/home/user/process_docs.cpp"

EXPECTED_TXT_FILES = {
    "doc_01.txt": b"Apple docs\n",
    "doc_02.txt": b"Banana docs\n",
    "doc_03.txt": b"Cherry docs\n",
    "doc_04.txt": b"Mango docs\n",
    "doc_05.txt": b"Zebra docs\n",
}

EXPECTED_CHUNKS = {
    "diagram.dat.chunk001": 100000,
    "diagram.dat.chunk002": 100000,
    "diagram.dat.chunk003": 50000,
    "screenshot.dat.chunk001": 100000,
    "screenshot.dat.chunk002": 50000,
}

OLD_FILES = [
    "apple.txt", "zebra.txt", "mango.txt", "banana.txt", "cherry.txt",
    "diagram.dat", "screenshot.dat"
]


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def expected_payload_files():
    return sorted(list(EXPECTED_TXT_FILES) + list(EXPECTED_CHUNKS))


def assert_manifest_matches(directory, expected_files):
    manifest_path = os.path.join(directory, "manifest.tsv")
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."

    with open(manifest_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_files), (
        f"Manifest should have {len(expected_files)} lines, but has {len(lines)}."
    )

    for i, line in enumerate(lines):
        parts = line.split('\t')
        assert len(parts) == 3, f"Manifest line {i+1} is not correctly tab-separated: {line}"
        filename, size, sha256 = parts
        assert filename == expected_files[i], (
            f"Manifest line {i+1} filename mismatch. Expected {expected_files[i]}, got {filename}."
        )

        filepath = os.path.join(directory, filename)
        assert os.path.isfile(filepath), f"File {filename} listed in manifest does not exist."
        actual_size = str(os.path.getsize(filepath))
        assert size == actual_size, (
            f"Manifest line {i+1} size mismatch for {filename}. Expected {actual_size}, got {size}."
        )
        actual_sha256 = get_sha256(filepath)
        assert sha256 == actual_sha256, (
            f"Manifest line {i+1} SHA256 mismatch for {filename}. Expected {actual_sha256}, got {sha256}."
        )


def test_cpp_program_exists():
    assert os.path.isfile(CPP_SOURCE), f"C++ source {CPP_SOURCE} does not exist."
    assert os.path.isfile(CPP_BIN), f"C++ program {CPP_BIN} does not exist."
    assert os.access(CPP_BIN, os.X_OK), f"C++ program {CPP_BIN} is not executable."
    with open(CPP_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{CPP_BIN} is not a compiled native executable."


def test_old_files_deleted():
    for old_file in OLD_FILES:
        filepath = os.path.join(DRAFTS_DIR, old_file)
        assert not os.path.exists(filepath), f"Original file {old_file} was not deleted."


def test_renamed_txt_files():
    for filename, expected_content in EXPECTED_TXT_FILES.items():
        filepath = os.path.join(DRAFTS_DIR, filename)
        assert os.path.isfile(filepath), f"Renamed file {filename} does not exist."
        with open(filepath, "rb") as f:
            content = f.read()
        assert content == expected_content, (
            f"Content of {filename} is incorrect. Expected {expected_content}, got {content}."
        )


def test_chunked_dat_files():
    for filename, expected_size in EXPECTED_CHUNKS.items():
        filepath = os.path.join(DRAFTS_DIR, filename)
        assert os.path.isfile(filepath), f"Chunk file {filename} does not exist."
        actual_size = os.path.getsize(filepath)
        assert actual_size == expected_size, (
            f"Size of {filename} is {actual_size}, expected {expected_size}."
        )


def test_manifest_file():
    assert_manifest_matches(DRAFTS_DIR, expected_payload_files())


def test_no_unexpected_draft_files():
    expected = set(expected_payload_files()) | {"manifest.tsv"}
    assert set(os.listdir(DRAFTS_DIR)) == expected, (
        "Drafts directory contains missing or unexpected files."
    )


def test_release_tar_gz():
    assert os.path.isfile(TAR_FILE), f"Archive {TAR_FILE} does not exist."
    expected_files = expected_payload_files() + ["manifest.tsv"]

    with tarfile.open(TAR_FILE, "r:gz") as tar:
        members = tar.getmembers()
        names = [member.name for member in members]

        assert len(names) == len(expected_files), (
            f"Archive should contain exactly {len(expected_files)} files, but contains {len(names)}."
        )
        for member in members:
            assert "/" not in member.name, (
                f"Archive should not contain outer folder structure, but found {member.name}."
            )
            assert member.name in expected_files, f"Archive contains unexpected file {member.name}."
            assert member.isfile(), f"Archive member {member.name} is not a regular file."
            archived = tar.extractfile(member).read()
            with open(os.path.join(DRAFTS_DIR, member.name), "rb") as f:
                on_disk = f.read()
            assert archived == on_disk, (
                f"Archived content for {member.name} does not match the drafts directory."
            )


def test_executable_performs_transformations_on_fresh_random_assets():
    parent = os.path.dirname(DRAFTS_DIR)
    backup_root = tempfile.mkdtemp(prefix="verifier-drafts-")
    backup = os.path.join(backup_root, "drafts")
    os.rename(DRAFTS_DIR, backup)

    diagram = os.urandom(250000)
    screenshot = os.urandom(150000)
    text_inputs = {
        "apple.txt": b"Apple docs\n",
        "zebra.txt": b"Zebra docs\n",
        "mango.txt": b"Mango docs\n",
        "banana.txt": b"Banana docs\n",
        "cherry.txt": b"Cherry docs\n",
    }

    try:
        os.mkdir(DRAFTS_DIR)
        for name, content in text_inputs.items():
            with open(os.path.join(DRAFTS_DIR, name), "wb") as f:
                f.write(content)
        with open(os.path.join(DRAFTS_DIR, "diagram.dat"), "wb") as f:
            f.write(diagram)
        with open(os.path.join(DRAFTS_DIR, "screenshot.dat"), "wb") as f:
            f.write(screenshot)

        result = subprocess.run(
            [CPP_BIN], cwd=parent, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=30, check=False
        )
        assert result.returncode == 0, (
            f"Compiled program failed on fresh inputs with code {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )

        for filename, expected_content in EXPECTED_TXT_FILES.items():
            with open(os.path.join(DRAFTS_DIR, filename), "rb") as f:
                assert f.read() == expected_content, f"Program produced incorrect {filename}."

        for filename, expected_size in EXPECTED_CHUNKS.items():
            path = os.path.join(DRAFTS_DIR, filename)
            assert os.path.isfile(path), f"Program did not create {filename}."
            assert os.path.getsize(path) == expected_size, f"Program created wrong-sized {filename}."

        rebuilt_diagram = b"".join(
            open(os.path.join(DRAFTS_DIR, f"diagram.dat.chunk{i:03d}"), "rb").read()
            for i in range(1, 4)
        )
        rebuilt_screenshot = b"".join(
            open(os.path.join(DRAFTS_DIR, f"screenshot.dat.chunk{i:03d}"), "rb").read()
            for i in range(1, 3)
        )
        assert rebuilt_diagram == diagram, "Diagram chunks do not reconstruct the random input."
        assert rebuilt_screenshot == screenshot, "Screenshot chunks do not reconstruct the random input."

        for old_file in OLD_FILES:
            assert not os.path.exists(os.path.join(DRAFTS_DIR, old_file)), (
                f"Program left original file {old_file}."
            )

        payload = expected_payload_files()
        assert_manifest_matches(DRAFTS_DIR, payload)
        assert set(os.listdir(DRAFTS_DIR)) == set(payload) | {"manifest.tsv"}, (
            "Program left temporary or unexpected files in drafts."
        )
    finally:
        if os.path.exists(DRAFTS_DIR):
            shutil.rmtree(DRAFTS_DIR)
        os.rename(backup, DRAFTS_DIR)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
