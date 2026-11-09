#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import hashlib

def test_extracted_directory_and_files():
    extracted_dir = "/home/user/extracted"
    assert os.path.isdir(extracted_dir), f"{extracted_dir} does not exist or is not a directory"

    expected_files = {"doc1.txt", "doc2.txt", "deadbeef.blob", "cafebabe.blob"}
    actual_files = set(os.listdir(extracted_dir))

    assert actual_files == expected_files, f"Files in {extracted_dir} do not match expected. Found: {actual_files}"

def test_text_files_utf8_conversion():
    doc1_path = "/home/user/extracted/doc1.txt"
    doc2_path = "/home/user/extracted/doc2.txt"

    # Read as bytes to verify UTF-8 encoding
    with open(doc1_path, "rb") as f:
        doc1_bytes = f.read()
    with open(doc2_path, "rb") as f:
        doc2_bytes = f.read()

    expected_doc1 = "Crème brûlée\n".encode("utf-8")
    expected_doc2 = "El Niño\n".encode("utf-8")

    assert doc1_bytes == expected_doc1, f"Content of {doc1_path} does not match expected UTF-8 encoding"
    assert doc2_bytes == expected_doc2, f"Content of {doc2_path} does not match expected UTF-8 encoding"

def test_blob_files_renaming():
    deadbeef_path = "/home/user/extracted/deadbeef.blob"
    cafebabe_path = "/home/user/extracted/cafebabe.blob"

    with open(deadbeef_path, "rb") as f:
        deadbeef_bytes = f.read()
    with open(cafebabe_path, "rb") as f:
        cafebabe_bytes = f.read()

    assert deadbeef_bytes == b"\xde\xad\xbe\xef\x00\x01\x02\x03", f"Content of {deadbeef_path} is incorrect"
    assert cafebabe_bytes == b"\xca\xfe\xba\xbe\x04\x05\x06\x07", f"Content of {cafebabe_path} is incorrect"

def test_manifest_log():
    manifest_path = "/home/user/manifest.log"
    assert os.path.isfile(manifest_path), f"{manifest_path} does not exist"

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Manifest should contain exactly 4 lines, found {len(lines)}"

    # Compute expected hashes
    extracted_dir = "/home/user/extracted"
    expected_hashes = {}
    for fname in ["cafebabe.blob", "deadbeef.blob", "doc1.txt", "doc2.txt"]:
        fpath = os.path.join(extracted_dir, fname)
        with open(fpath, "rb") as f:
            expected_hashes[fname] = hashlib.sha256(f.read()).hexdigest()

    # Check lines and sorting
    expected_lines = [
        f"{expected_hashes['cafebabe.blob']}  cafebabe.blob",
        f"{expected_hashes['deadbeef.blob']}  deadbeef.blob",
        f"{expected_hashes['doc1.txt']}  doc1.txt",
        f"{expected_hashes['doc2.txt']}  doc2.txt",
    ]

    # allow single or double spaces before filename as standard sha256sum does
    parsed_lines = []
    for line in lines:
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            parsed_lines.append(f"{parts[0]}  {parts[1].lstrip('* ')}")

    assert parsed_lines == expected_lines, "Manifest lines do not match expected sorted sha256sum output"

def test_tarball_creation():
    tarball_path = "/home/user/curated_artifacts.tar.gz"
    assert os.path.isfile(tarball_path), f"{tarball_path} does not exist"
    assert tarfile.is_tarfile(tarball_path), f"{tarball_path} is not a valid tar archive"

    with tarfile.open(tarball_path, "r:gz") as tar:
        names = tar.getnames()

        # Check that extracted/ and the 4 files are in the tarball
        # They could be stored as extracted/... or ./extracted/...
        normalized_names = [os.path.normpath(n) for n in names]

        expected_basenames = {"doc1.txt", "doc2.txt", "deadbeef.blob", "cafebabe.blob"}
        found_basenames = set()
        has_extracted_dir = False

        for name in normalized_names:
            parts = name.split(os.sep)
            if "extracted" in parts:
                has_extracted_dir = True
                basename = parts[-1]
                if basename in expected_basenames:
                    found_basenames.add(basename)

        assert has_extracted_dir, "Tarball does not contain the 'extracted' directory"
        assert found_basenames == expected_basenames, f"Tarball does not contain all expected files. Found: {found_basenames}"

        # Require exactly the processed directory and its four files, with no
        # duplicate, extra, nested, absolute, or traversal-based members.
        def canonical_name(name):
            while name.startswith("./"):
                name = name[2:]
            return name.rstrip("/")

        expected_members = {
            "extracted",
            "extracted/doc1.txt",
            "extracted/doc2.txt",
            "extracted/deadbeef.blob",
            "extracted/cafebabe.blob",
        }
        canonical_members = [canonical_name(member.name) for member in tar.getmembers()]
        assert len(canonical_members) == len(expected_members), "Tarball contains extra or duplicate members"
        assert set(canonical_members) == expected_members, f"Tarball members do not exactly match expected: {canonical_members}"

        members = {canonical_name(member.name): member for member in tar.getmembers()}
        assert members["extracted"].isdir(), "The extracted root member is not a directory"

        for basename in expected_basenames:
            archive_name = f"extracted/{basename}"
            member = members[archive_name]
            assert member.isfile(), f"{archive_name} is not a regular file"
            archived_file = tar.extractfile(member)
            assert archived_file is not None, f"Could not read {archive_name} from tarball"
            archived_bytes = archived_file.read()
            with open(os.path.join("/home/user/extracted", basename), "rb") as f:
                expected_bytes = f.read()
            assert archived_bytes == expected_bytes, f"Archived content of {archive_name} does not match /home/user/extracted/{basename}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
