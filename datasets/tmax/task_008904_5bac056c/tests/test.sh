#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import tarfile
import tempfile
import hashlib
import pytest

ARCHIVE_PATH = "/home/user/release_archive.tar.gz"
MANIFEST_PATH = "/home/user/manifest.json"
STAGING_PATH = "/home/user/artifact_staging"
EXPECTED_FILES = {
    "bin/app_x86": {"file_type": "elf", "e_machine": "0x3e"},
    "bin/app_arm": {"file_type": "elf", "e_machine": "0x28"},
    "docs/release_notes.txt": {"file_type": "text"},
    "hardware/case_print.gcode": {"file_type": "text"},
}
EXPECTED_TEXT = {
    "docs/release_notes.txt": "Release Notes: v1.0.0\nFixed: Buffer overflow in parser.\n",
    "hardware/case_print.gcode": "; GCode Header\n; Temperature: 210°C\nG28\nG1 X10 Y10\n",
}


def regular_files(root):
    result = set()
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            path = os.path.join(dirpath, name)
            assert os.path.isfile(path) and not os.path.islink(path), f"{path} is not a regular file."
            result.add(os.path.relpath(path, root).replace(os.sep, "/"))
    return result


def derive_metadata(data, rel_path):
    if data.startswith(b"\x7fELF"):
        assert len(data) >= 20, f"ELF file {rel_path} has a truncated header."
        assert data[4] in (1, 2), f"ELF file {rel_path} has an invalid ELF class."
        assert data[5] in (1, 2), f"ELF file {rel_path} has invalid byte order metadata."
        byteorder = "little" if data[5] == 1 else "big"
        machine = int.from_bytes(data[18:20], byteorder=byteorder)
        return "elf", hex(machine)
    if rel_path.endswith(".txt") or rel_path.endswith(".gcode"):
        return "text", None
    return "unknown", None


@pytest.fixture(scope="module")
def extracted_archive():
    """Extracts the release archive to a temporary directory and yields the path."""
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
            for member in tar.getmembers():
                normalized = os.path.normpath(member.name)
                assert not os.path.isabs(member.name), "Archive contains an absolute path."
                assert normalized != ".." and not normalized.startswith("../"), "Archive contains path traversal."
                assert not member.issym() and not member.islnk(), "Archive must not use links for artifacts."
            tar.extractall(path=tmpdir)
        yield tmpdir


def test_archive_contents_and_manifest_exists(extracted_archive):
    """Test that the archive contains the manifest.json and the artifact_staging directory."""
    manifest_path = os.path.join(extracted_archive, "manifest.json")
    assert os.path.isfile(manifest_path), "manifest.json is missing from the root of the archive."

    staging_dir = os.path.join(extracted_archive, "artifact_staging")
    assert os.path.isdir(staging_dir), "artifact_staging directory is missing from the archive."


def test_external_manifest_exists_and_matches_archive(extracted_archive):
    assert os.path.isfile(MANIFEST_PATH), f"Manifest {MANIFEST_PATH} does not exist outside the archive."
    archived_manifest = os.path.join(extracted_archive, "manifest.json")
    with open(MANIFEST_PATH, "rb") as f:
        external_data = f.read()
    with open(archived_manifest, "rb") as f:
        archived_data = f.read()
    assert external_data == archived_data, "Archived manifest.json does not match /home/user/manifest.json."


def test_manifest_structure_and_metadata(extracted_archive):
    """Test that the manifest contains the correct metadata for each file."""
    manifest_path = os.path.join(extracted_archive, "manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("manifest.json is not a valid JSON file.")

    assert isinstance(manifest, dict), "manifest.json must contain a JSON dictionary."

    for rel_path, expected_meta in EXPECTED_FILES.items():
        assert rel_path in manifest, f"File {rel_path} is missing from manifest.json."

        file_meta = manifest[rel_path]
        assert "sha256" in file_meta, f"Missing 'sha256' for {rel_path} in manifest.json."
        assert file_meta.get("file_type") == expected_meta["file_type"], f"Incorrect file_type for {rel_path}."

        if expected_meta["file_type"] == "elf":
            assert "e_machine" in file_meta, f"Missing 'e_machine' for {rel_path}."
            assert file_meta["e_machine"].lower() == expected_meta["e_machine"], f"Incorrect e_machine for {rel_path}."


def test_all_staging_files_are_archived_and_manifested(extracted_archive):
    assert os.path.isdir(STAGING_PATH), f"Staging directory {STAGING_PATH} does not exist."
    live_files = regular_files(STAGING_PATH)
    archived_root = os.path.join(extracted_archive, "artifact_staging")
    archived_files = regular_files(archived_root)

    for rel_path in EXPECTED_FILES:
        assert rel_path in live_files, f"Original staging file {rel_path} is missing."

    with open(os.path.join(extracted_archive, "manifest.json"), "r", encoding="utf-8") as f:
        manifest = json.load(f)

    assert set(manifest.keys()) == live_files, "Manifest does not describe every current staging file exactly once."
    assert archived_files == live_files, "Archive does not contain all and only the staging files."

    for rel_path in live_files:
        with open(os.path.join(STAGING_PATH, rel_path), "rb") as f:
            live_data = f.read()
        with open(os.path.join(archived_root, rel_path), "rb") as f:
            archived_data = f.read()
        assert archived_data == live_data, f"Archived file {rel_path} differs from the processed staging file."


def test_metadata_is_derived_from_archived_bytes(extracted_archive):
    with open(os.path.join(extracted_archive, "manifest.json"), "r", encoding="utf-8") as f:
        manifest = json.load(f)

    for rel_path, meta in manifest.items():
        assert isinstance(rel_path, str) and rel_path, "Manifest paths must be non-empty strings."
        normalized = os.path.normpath(rel_path)
        assert not os.path.isabs(rel_path) and normalized != ".." and not normalized.startswith("../"), \
            f"Unsafe manifest path: {rel_path}"
        assert isinstance(meta, dict), f"Metadata for {rel_path} must be a dictionary."

        full_path = os.path.join(extracted_archive, "artifact_staging", rel_path)
        with open(full_path, "rb") as f:
            data = f.read()
        actual_type, actual_machine = derive_metadata(data, rel_path)

        assert meta.get("file_type") == actual_type, f"file_type for {rel_path} was not derived from its bytes/name."
        if actual_type == "elf":
            assert isinstance(meta.get("e_machine"), str), f"Missing e_machine for ELF file {rel_path}."
            assert meta["e_machine"].lower() == actual_machine, \
                f"e_machine for {rel_path} does not match its ELF header."
        else:
            assert "e_machine" not in meta, f"Non-ELF file {rel_path} must not contain e_machine."


def test_text_files_are_utf8_encoded(extracted_archive):
    """Test that the text and gcode files in the archive are properly UTF-8 encoded."""
    text_files = [
        "artifact_staging/docs/release_notes.txt",
        "artifact_staging/hardware/case_print.gcode"
    ]

    for rel_path in text_files:
        full_path = os.path.join(extracted_archive, rel_path)
        assert os.path.isfile(full_path), f"File {rel_path} is missing from the archive."

        with open(full_path, "rb") as f:
            data = f.read()

        try:
            decoded_text = data.decode("utf-8")
        except UnicodeDecodeError:
            pytest.fail(f"File {rel_path} is not correctly encoded in UTF-8.")

        if "case_print.gcode" in rel_path:
            assert "210°C" in decoded_text, f"Expected character '°' not found or mangled in {rel_path}."


def test_all_manifest_text_files_are_utf8(extracted_archive):
    with open(os.path.join(extracted_archive, "manifest.json"), "r", encoding="utf-8") as f:
        manifest = json.load(f)
    for rel_path, meta in manifest.items():
        if meta.get("file_type") == "text":
            with open(os.path.join(extracted_archive, "artifact_staging", rel_path), "rb") as f:
                data = f.read()
            try:
                data.decode("utf-8")
            except UnicodeDecodeError:
                pytest.fail(f"File {rel_path} is not correctly encoded in UTF-8.")


def test_original_text_content_was_preserved(extracted_archive):
    for rel_path, expected in EXPECTED_TEXT.items():
        full_path = os.path.join(extracted_archive, "artifact_staging", rel_path)
        with open(full_path, "rb") as f:
            actual = f.read().decode("utf-8")
        assert actual == expected, f"Text content was not preserved while converting {rel_path}."


def test_hashes_match_manifest(extracted_archive):
    """Test that the SHA-256 hashes in the manifest match the actual files in the archive."""
    manifest_path = os.path.join(extracted_archive, "manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    for rel_path, meta in manifest.items():
        full_path = os.path.join(extracted_archive, "artifact_staging", rel_path)
        assert os.path.isfile(full_path), f"File {rel_path} referenced in manifest is missing from archive."

        with open(full_path, "rb") as f:
            file_data = f.read()

        actual_hash = hashlib.sha256(file_data).hexdigest()
        expected_hash = meta.get("sha256")

        assert actual_hash == expected_hash, f"SHA-256 hash mismatch for {rel_path}. Expected {expected_hash}, got {actual_hash}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
