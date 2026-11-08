#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import zipfile
import pytest

WORKSPACE = "/home/user/workspace"
EXTRACTED = os.path.join(WORKSPACE, "extracted")
BINARIES = os.path.join(WORKSPACE, "binaries")

EXPECTED_METADATA = (
    b'{\n'
    b'  "project_name": "LegacySystem",\n'
    b'  "project_version": "2.9.4-beta",\n'
    b'  "author": "dev_team"\n'
    b'}\n'
)
EXPECTED_README = b"Regular text file\n"
EXPECTED_CSV = "id,name\n1,Café\n2,Résumé\n".encode("utf-8")
EXPECTED_FILES = {
    "metadata.json": EXPECTED_METADATA,
    "readme.txt": EXPECTED_README,
    "subdir/data.csv": EXPECTED_CSV,
}


def read_regular_file(path):
    assert os.path.isfile(path), f"{path} is missing or is not a regular file."
    assert not os.path.islink(path), f"{path} must not be a symbolic link."
    with open(path, "rb") as f:
        return f.read()


def extracted_file_map():
    result = {}
    for root, dirs, files in os.walk(EXTRACTED, followlinks=False):
        for name in dirs:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Unexpected symbolic-link directory: {path}"
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, EXTRACTED).replace(os.sep, "/")
            result[rel] = read_regular_file(path)
    return result


def test_elf_binaries_moved():
    binaries_dir = BINARIES
    extracted_dir = EXTRACTED

    # Expected binaries
    ls_bin = os.path.join(binaries_dir, "ls_bin")
    pwd_bin = os.path.join(binaries_dir, "pwd_bin")

    assert os.path.exists(ls_bin), "ls_bin was not moved to binaries directory."
    assert os.path.exists(pwd_bin), "pwd_bin was not moved to binaries directory."

    # Check they are ELF by reading magic bytes
    for bin_file in [ls_bin, pwd_bin]:
        with open(bin_file, "rb") as f:
            magic = f.read(4)
            assert magic == b"\x7fELF", f"{bin_file} is not an ELF binary."

    # Check they are removed from extracted
    assert not os.path.exists(os.path.join(extracted_dir, "ls_bin")), "ls_bin was not removed from extracted directory."
    assert not os.path.exists(os.path.join(extracted_dir, "subdir", "pwd_bin")), "pwd_bin was not removed from extracted directory."

    # The setup copied these binaries byte-for-byte from the system binaries.
    assert read_regular_file(ls_bin) == read_regular_file("/bin/ls"), "ls_bin is not the original archived /bin/ls binary."
    assert read_regular_file(pwd_bin) == read_regular_file("/bin/pwd"), "pwd_bin is not the original archived /bin/pwd binary."


def test_csv_encoding_converted():
    csv_file = os.path.join(EXTRACTED, "subdir", "data.csv")
    assert os.path.exists(csv_file), f"{csv_file} is missing."

    with open(csv_file, "rb") as f:
        content = f.read()

    try:
        decoded = content.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail("CSV file is not valid UTF-8.")

    # Check that it contains the expected characters (Café, Résumé)
    assert "Café" in decoded, "Expected string 'Café' not found in UTF-8 decoded CSV."
    assert "Résumé" in decoded, "Expected string 'Résumé' not found in UTF-8 decoded CSV."
    assert content == EXPECTED_CSV, "CSV contents do not exactly match the UTF-8 conversion of the archived file."


def test_extracted_contents_are_complete_and_exact():
    assert os.path.isdir(EXTRACTED), "extracted directory is missing."
    actual = extracted_file_map()
    assert set(actual) == set(EXPECTED_FILES), f"Unexpected extracted file set: {sorted(actual)}"
    for name, expected in EXPECTED_FILES.items():
        assert actual[name] == expected, f"Extracted file {name} does not match the archived content."


def test_version_extracted():
    version_file = os.path.join(WORKSPACE, "version.txt")
    assert os.path.exists(version_file), "version.txt was not created."

    with open(version_file, "r", encoding="utf-8") as f:
        version = f.read().strip()

    assert version == "2.9.4-beta", f"Expected version '2.9.4-beta', got '{version}'."
    metadata_path = os.path.join(EXTRACTED, "metadata.json")
    with open(metadata_path, "r", encoding="utf-8") as f:
        metadata_version = json.load(f)["project_version"]
    assert read_regular_file(version_file) == metadata_version.encode("utf-8") + b"\n" or read_regular_file(version_file) == metadata_version.encode("utf-8"), \
        "version.txt must contain only the project_version value, optionally followed by one newline."


def test_zip_archive_created():
    zip_path = os.path.join(WORKSPACE, "cleaned_project.zip")
    assert os.path.exists(zip_path), "cleaned_project.zip was not created."
    assert zipfile.is_zipfile(zip_path), "cleaned_project.zip is not a valid zip archive."

    with zipfile.ZipFile(zip_path, "r") as z:
        namelist = z.namelist()

        # Check expected files are in the zip
        assert "metadata.json" in namelist, "metadata.json missing from zip."
        assert "readme.txt" in namelist, "readme.txt missing from zip."
        assert "subdir/data.csv" in namelist, "subdir/data.csv missing from zip."

        # Check ELF binaries are NOT in the zip
        assert "ls_bin" not in namelist, "ls_bin should not be in the zip."
        assert "subdir/pwd_bin" not in namelist, "pwd_bin should not be in the zip."

        file_infos = [info for info in z.infolist() if not info.is_dir()]
        archived_names = [info.filename for info in file_infos]
        assert len(archived_names) == len(set(archived_names)), "Zip contains duplicate file entries."
        assert set(archived_names) == set(EXPECTED_FILES), f"Unexpected zip file set: {sorted(archived_names)}"
        for info in file_infos:
            assert not info.filename.startswith("/") and ".." not in info.filename.split("/"), \
                f"Unsafe zip entry path: {info.filename}"
            assert z.read(info) == EXPECTED_FILES[info.filename], \
                f"Archived contents of {info.filename} do not match the cleaned extracted file."

        # Also compare the archive against the actual current extracted tree.
        current = extracted_file_map()
        for name, content in current.items():
            assert z.read(name) == content, f"Zip entry {name} differs from the extracted file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
