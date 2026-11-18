#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import stat
import tarfile
import zipfile
import pytest

DRAFTS_DIR = "/home/user/extracted_docs/drafts"
EXPECTED_RENAMED = {
    "release_notes_v1.md": b"Draft 1\n",
    "api_spec_draft.md": b"Draft 2\n",
    "user_guide.md": b"Draft 3\n",
}
EXPECTED_ARCHIVE_FILES = {
    "drafts/Release Notes v1.txt": b"Draft 1\n",
    "drafts/API Spec Draft.txt": b"Draft 2\n",
    "drafts/User Guide.txt": b"Draft 3\n",
}


def test_extracted_docs_directory_exists():
    """Verify that the extracted_docs/drafts directory was created."""
    assert os.path.isdir(DRAFTS_DIR), f"Expected directory {DRAFTS_DIR} to exist."


def test_nested_archive_was_extracted_intact():
    """Verify the nested archive and its original payload, not just output names."""
    zip_path = "/home/user/docs_archive.zip"
    extracted_tar_path = "/home/user/extracted_docs/drafts.tar.gz"

    assert os.path.isfile(zip_path), f"Expected source archive {zip_path} to exist."
    assert os.path.isfile(extracted_tar_path), (
        f"Expected nested archive {extracted_tar_path} to have been extracted."
    )
    assert not os.path.islink(extracted_tar_path), "Extracted nested archive must be a regular file."
    assert stat.S_ISREG(os.stat(extracted_tar_path, follow_symlinks=False).st_mode)

    with zipfile.ZipFile(zip_path, "r") as outer:
        assert "drafts.tar.gz" in outer.namelist(), "Source zip is missing drafts.tar.gz."
        nested_bytes = outer.read("drafts.tar.gz")

    with open(extracted_tar_path, "rb") as f:
        assert f.read() == nested_bytes, "Extracted drafts.tar.gz differs from the zip member."

    with tarfile.open(fileobj=io.BytesIO(nested_bytes), mode="r:gz") as archive:
        actual_payload = {
            member.name: archive.extractfile(member).read()
            for member in archive.getmembers()
            if member.isfile()
        }

    assert actual_payload == EXPECTED_ARCHIVE_FILES, (
        "The nested archive does not contain the expected original draft files and contents."
    )


def test_renamed_markdown_files():
    """Verify that the text files were properly renamed to markdown files."""
    assert os.path.isdir(DRAFTS_DIR), "Drafts directory missing."

    files = os.listdir(DRAFTS_DIR)

    expected_files = {
        "release_notes_v1.md",
        "api_spec_draft.md",
        "user_guide.md"
    }

    md_files = {f for f in files if f.endswith(".md")}
    txt_files = {f for f in files if f.endswith(".txt")}

    assert not txt_files, f"Found unexpected .txt files in {DRAFTS_DIR}: {txt_files}"
    assert md_files == expected_files, f"Expected markdown files {expected_files}, but found {md_files}"
    assert set(files) == expected_files, f"Unexpected files in {DRAFTS_DIR}: {set(files) - expected_files}"

    for filename, expected_content in EXPECTED_RENAMED.items():
        path = os.path.join(DRAFTS_DIR, filename)
        assert not os.path.islink(path), f"{path} must be a renamed regular file, not a symlink."
        assert stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode), f"{path} is not a regular file."
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Contents of {filename} were not preserved during renaming."


def test_alice_commits_json_exists_and_valid():
    """Verify that alice_commits.json exists and contains the correct structured data."""
    json_path = "/home/user/alice_commits.json"
    assert os.path.isfile(json_path), f"Expected JSON file {json_path} to exist."

    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {json_path} as valid JSON: {e}")

    assert isinstance(data, list), "JSON output must be a list of objects."
    assert len(data) == 2, f"Expected exactly 2 commits by Alice Writer, found {len(data)}."

    expected_data = [
        {
            "commit": "3c4d5e6",
            "date": "2023-10-11",
            "message": "Initial draft of API endpoints.\nFormatting fixes."
        },
        {
            "commit": "1d2e3f4",
            "date": "2023-10-14",
            "message": "Added Webhook documentation.\nFixed typos in overview.\nClarified rate limits."
        }
    ]

    for i, expected_entry in enumerate(expected_data):
        assert isinstance(data[i], dict), f"Entry {i} must be an object."
        assert set(data[i].keys()) == {"commit", "date", "message"}, (
            f"Entry {i} must contain exactly the keys commit, date, and message."
        )
        assert data[i].get("commit") == expected_entry["commit"], f"Entry {i} commit mismatch."
        assert data[i].get("date") == expected_entry["date"], f"Entry {i} date mismatch."
        assert data[i].get("message") == expected_entry["message"], f"Entry {i} message mismatch. Check indentation and newlines."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
