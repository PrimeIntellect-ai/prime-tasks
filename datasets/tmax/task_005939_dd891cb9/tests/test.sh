#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import tarfile
import tempfile
import zipfile

FINAL_DIR = pathlib.Path("/home/user/final_docs")
EXTRACTED_DIR = pathlib.Path("/home/user/extracted")
ARCHIVE_PATH = pathlib.Path("/home/user/legacy_docs.zip")
MANIFEST_PATH = pathlib.Path("/home/user/manifest.json")

EXPECTED_FILES = [
    "engineering_api_auth.md",
    "engineering_api_endpoints.md",
    "sales_pitch_contacts.md",
    "sales_pitch_deck.md",
]

KNOWN_EXPECTED_CONTENTS = {
    "engineering_api_auth.md": b"## API Authentication\nUse JWT tokens.",
    "engineering_api_endpoints.md": b"# Original File: endpoints.txt\n\nGET /users\nPOST /users",
    "sales_pitch_contacts.md": b"# Contacts\n- John Doe\n- Jane Smith",
    "sales_pitch_deck.md": b"# Original File: deck.txt\n\nSlide 1: Intro\nSlide 2: Synergy",
}

EXPECTED_MANIFEST = [
    "/home/user/final_docs/engineering_api_auth.md",
    "/home/user/final_docs/engineering_api_endpoints.md",
    "/home/user/final_docs/sales_pitch_contacts.md",
    "/home/user/final_docs/sales_pitch_deck.md",
]


def derive_expected_outputs():
    assert ARCHIVE_PATH.exists(), f"Source archive {ARCHIVE_PATH} is missing."
    assert ARCHIVE_PATH.is_file(), f"Source archive {ARCHIVE_PATH} is not a file."

    with tempfile.TemporaryDirectory() as temporary_directory:
        root = pathlib.Path(temporary_directory)
        with zipfile.ZipFile(ARCHIVE_PATH, "r") as archive:
            archive.extractall(root)

        while True:
            nested_archives = sorted(
                path for path in root.rglob("*")
                if path.is_file() and (
                    path.name.endswith(".zip") or path.name.endswith(".tar.gz")
                )
            )
            if not nested_archives:
                break

            for nested_archive in nested_archives:
                destination = nested_archive.parent
                if nested_archive.name.endswith(".zip"):
                    with zipfile.ZipFile(nested_archive, "r") as archive:
                        archive.extractall(destination)
                else:
                    with tarfile.open(nested_archive, "r:gz") as archive:
                        archive.extractall(destination)
                nested_archive.unlink()

        expected = {}
        for source in sorted(root.rglob("*")):
            if not source.is_file():
                continue
            relative = source.relative_to(root)
            flattened = relative.as_posix().replace("/", "_")
            if source.suffix == ".md":
                output_name = flattened
                output_content = source.read_bytes()
            elif source.suffix == ".txt":
                output_name = flattened[:-4] + ".md"
                output_content = (
                    f"# Original File: {source.name}\n\n".encode("utf-8")
                    + source.read_bytes()
                )
            else:
                raise AssertionError(f"Unexpected source file in archive: {relative}")

            assert output_name not in expected, f"Flattened filename collision: {output_name}"
            expected[output_name] = output_content

        return expected


def test_final_docs_directory_exists():
    assert os.path.exists("/home/user/final_docs"), "Directory /home/user/final_docs/ does not exist."
    assert os.path.isdir("/home/user/final_docs"), "/home/user/final_docs/ is not a directory."


def test_expected_files_exist():
    for filename in EXPECTED_FILES:
        filepath = os.path.join("/home/user/final_docs", filename)
        assert os.path.exists(filepath), f"Expected file {filepath} is missing."
        assert os.path.isfile(filepath), f"{filepath} is not a file."


def test_converted_file_contents():
    endpoints_path = "/home/user/final_docs/engineering_api_endpoints.md"
    deck_path = "/home/user/final_docs/sales_pitch_deck.md"

    with open(endpoints_path, "r") as f:
        endpoints_content = f.read()
    assert endpoints_content.startswith("# Original File: endpoints.txt\n\n"), f"File {endpoints_path} does not have the correct header."
    assert "GET /users\nPOST /users" in endpoints_content, f"File {endpoints_path} does not contain the original content."

    with open(deck_path, "r") as f:
        deck_content = f.read()
    assert deck_content.startswith("# Original File: deck.txt\n\n"), f"File {deck_path} does not have the correct header."
    assert "Slide 1: Intro\nSlide 2: Synergy" in deck_content, f"File {deck_path} does not contain the original content."


def test_manifest_json():
    assert MANIFEST_PATH.exists(), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, "r") as f:
        try:
            manifest_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Manifest file {MANIFEST_PATH} is not valid JSON."

    assert isinstance(manifest_data, list), "Manifest JSON is not a list."
    assert manifest_data == EXPECTED_MANIFEST, "Manifest JSON does not contain the expected sorted list of absolute paths."


def test_extracted_directory_cleanup():
    assert EXTRACTED_DIR.exists(), f"Directory {EXTRACTED_DIR} does not exist."

    for root, dirs, files in os.walk(EXTRACTED_DIR):
        for file in files:
            assert not file.endswith(".zip"), f"Found zip file {file} in {root}."
            assert not file.endswith(".tar.gz"), f"Found tar.gz file {file} in {root}."
            assert not file.endswith(".txt"), f"Found txt file {file} in {root}."
            assert not file.endswith(".md"), f"Found md file {file} in {root}."


def test_all_outputs_exactly_match_recursively_extracted_archive():
    expected = derive_expected_outputs()

    # Ensure the source archive itself still represents the supplied fixture,
    # rather than accepting outputs derived from a rewritten archive.
    assert expected == KNOWN_EXPECTED_CONTENTS, "The supplied legacy_docs.zip was altered or has unexpected contents."

    actual_entries = sorted(path.name for path in FINAL_DIR.iterdir())
    assert actual_entries == sorted(expected), "final_docs contains missing, extra, or incorrectly named entries."

    for filename, expected_content in expected.items():
        output = FINAL_DIR / filename
        assert output.is_file(), f"Expected regular file {output}."
        assert output.read_bytes() == expected_content, f"File {output} does not exactly match its source/conversion."

    with open(MANIFEST_PATH, "r", encoding="utf-8") as manifest_file:
        manifest = json.load(manifest_file)
    derived_manifest = sorted(str(FINAL_DIR / filename) for filename in expected)
    assert manifest == derived_manifest, "Manifest does not exactly catalog all derived output files."

    remaining_entries = [
        str(path) for path in EXTRACTED_DIR.rglob("*")
        if path.is_file() or path.is_symlink()
    ]
    assert remaining_entries == [], f"Extracted directory still contains files: {remaining_entries}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
