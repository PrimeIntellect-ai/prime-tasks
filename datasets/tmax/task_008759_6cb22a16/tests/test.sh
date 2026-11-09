#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import tarfile
import zipfile
import pytest

ORGANIZED_DIR = "/home/user/organized_data"
RAW_DATA_DIR = "/home/user/raw_data"
FINAL_ARCHIVE = "/home/user/final_dataset.tar.gz"
LOG_PATH = "/home/user/processing_log.txt"

EXPECTED_FILES = {
    "TUN_reading_01.tar.gz",
    "GLA_reading_02.zip",
    "OCE_reading_03.tar.gz",
}

EXPECTED_LINES = [
    "/home/user/raw_data/site_A/2021/reading_01.tar.gz -> TUN_reading_01.tar.gz",
    "/home/user/raw_data/site_A/2022/reading_02.zip -> GLA_reading_02.zip",
    "/home/user/raw_data/site_B/logs/reading_03.tar.gz -> OCE_reading_03.tar.gz",
]


def read_metadata(archive_path):
    if archive_path.endswith(".tar.gz"):
        with tarfile.open(archive_path, "r:gz") as archive:
            member = archive.getmember("metadata.txt")
            extracted = archive.extractfile(member)
            assert extracted is not None
            return extracted.read().decode("utf-8")
    if archive_path.endswith(".zip"):
        with zipfile.ZipFile(archive_path, "r") as archive:
            return archive.read("metadata.txt").decode("utf-8")
    raise AssertionError(f"Unsupported archive: {archive_path}")


def derive_expected_outputs():
    with open("/home/user/project_mapping.json", "r") as mapping_file:
        mapping = json.load(mapping_file)

    expected = {}
    expected_log = []
    for root, _, files in os.walk(RAW_DATA_DIR):
        for filename in files:
            if not (filename.endswith(".tar.gz") or filename.endswith(".zip")):
                continue
            source = os.path.join(root, filename)
            metadata = read_metadata(source)
            project_lines = [line for line in metadata.splitlines() if line.startswith("Project: ")]
            assert len(project_lines) == 1, f"Invalid project metadata in {source}"
            project = project_lines[0][len("Project: "):]
            if project not in mapping:
                continue
            destination_name = f"{mapping[project]}_{filename}"
            assert destination_name not in expected, f"Output name collision: {destination_name}"
            expected[destination_name] = source
            expected_log.append(f"{source} -> {destination_name}")

    return expected, sorted(expected_log)


def test_organized_data_directory():
    assert os.path.isdir(ORGANIZED_DIR), f"Directory {ORGANIZED_DIR} does not exist."
    files = set(os.listdir(ORGANIZED_DIR))
    assert files == EXPECTED_FILES, (
        f"Expected files {EXPECTED_FILES} in {ORGANIZED_DIR}, but found {files}."
    )


def test_organized_archives_are_exact_source_copies():
    expected, _ = derive_expected_outputs()
    assert set(expected) == EXPECTED_FILES

    for destination_name, source_path in expected.items():
        destination_path = os.path.join(ORGANIZED_DIR, destination_name)
        assert os.path.isfile(destination_path), f"Missing organized archive {destination_path}"
        with open(source_path, "rb") as source_file, open(destination_path, "rb") as destination_file:
            assert destination_file.read() == source_file.read(), (
                f"{destination_path} is not an exact copy of {source_path}"
            )
        # Also ensure the copied file remains a valid archive containing readable metadata.
        assert read_metadata(destination_path) == read_metadata(source_path)


def test_final_dataset_archive():
    assert os.path.isfile(FINAL_ARCHIVE), f"Archive {FINAL_ARCHIVE} does not exist."

    try:
        with tarfile.open(FINAL_ARCHIVE, "r:gz") as archive:
            names = archive.getnames()
            basenames = {os.path.basename(name) for name in names if not name.endswith("/")}
            missing = EXPECTED_FILES - basenames
            assert not missing, f"Archive {FINAL_ARCHIVE} is missing expected files: {missing}"

            expected, _ = derive_expected_outputs()
            for destination_name, source_path in expected.items():
                matching = [
                    member for member in archive.getmembers()
                    if os.path.basename(member.name) == destination_name
                ]
                assert len(matching) == 1, (
                    f"Expected exactly one {destination_name} in {FINAL_ARCHIVE}, found {len(matching)}"
                )
                member = matching[0]
                assert member.isfile(), f"Archive member {member.name} is not a regular file"
                extracted = archive.extractfile(member)
                assert extracted is not None
                with open(source_path, "rb") as source_file:
                    assert extracted.read() == source_file.read(), (
                        f"Archive member {member.name} is not an exact copy of {source_path}"
                    )
    except tarfile.TarError:
        pytest.fail(f"File {FINAL_ARCHIVE} is not a valid tar.gz archive.")


def test_processing_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as log_file:
        lines = [line.strip() for line in log_file if line.strip()]

    assert lines == EXPECTED_LINES, (
        f"Log file contents do not match expected sorted output.\n"
        f"Expected:\n{EXPECTED_LINES}\nGot:\n{lines}"
    )

    _, derived_log = derive_expected_outputs()
    assert lines == derived_log, "Log does not match the archives and metadata found in raw_data"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
