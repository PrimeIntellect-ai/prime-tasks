#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tarfile
from pathlib import Path

import pytest

EXPECTED_FILES = [
    "app1_chunk_aa.txt",
    "app1_chunk_ab.txt",
    "app1_chunk_ac.txt",
    "app2_chunk_aa.txt",
    "db_sync_chunk_aa.txt",
    "db_sync_chunk_ab.txt",
    "db_sync_chunk_ac.txt",
    "db_sync_chunk_ad.txt",
    "db_sync_chunk_ae.txt"
]

SCRIPT_PATH = "/home/user/process_logs.sh"
SOURCE_ARCHIVE = "/home/user/incoming_logs.tar"
PROCESSING_DIR = Path("/home/user/processing")
FINAL_ARCHIVE = "/home/user/final_chunks.tar.gz"
REPORT_PATH = "/home/user/report.txt"


def normalized_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def source_files():
    result = {}
    with tarfile.open(SOURCE_ARCHIVE, "r:") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            name = normalized_member_name(member.name)
            assert name and not name.startswith("/") and ".." not in Path(name).parts
            extracted = tar.extractfile(member)
            assert extracted is not None
            result[name] = extracted.read()
    return result


def split_suffix(index):
    assert 0 <= index < 26 * 26
    return chr(ord("a") + index // 26) + chr(ord("a") + index % 26)


def expected_chunks():
    chunks = {}
    locations = {}
    for relative_name, data in source_files().items():
        path = Path(relative_name)
        if path.suffix != ".log":
            continue
        lines = data.splitlines(keepends=True)
        for index, start in enumerate(range(0, len(lines), 50)):
            chunk_name = f"{path.stem}_chunk_{split_suffix(index)}.txt"
            assert chunk_name not in chunks, f"Flat archive name collision for {chunk_name}"
            chunks[chunk_name] = b"".join(lines[start:start + 50])
            locations[str(path.parent / chunk_name)] = chunks[chunk_name]
    return chunks, locations


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."

    shutil.rmtree(PROCESSING_DIR, ignore_errors=True)
    for path in (FINAL_ARCHIVE, REPORT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_process_logs_script():
    script_path = "/home/user/process_logs.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."

    with open(script_path, "r") as f:
        content = f.read()

    assert "flock" in content, "The script must use 'flock' to obtain a file lock."


def test_report_txt():
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_FILES, f"Contents of {report_path} do not match the expected list of files."


def test_final_chunks_archive():
    archive_path = "/home/user/final_chunks.tar.gz"
    assert os.path.exists(archive_path), f"Archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()

    members_sorted = sorted(members)
    assert members_sorted == EXPECTED_FILES, (
        f"Contents of {archive_path} do not match the expected flat structure. "
        f"Expected {EXPECTED_FILES}, but got {members_sorted}."
    )


def test_extracted_source_and_chunk_contents():
    expected, expected_locations = expected_chunks()
    assert sorted(expected) == EXPECTED_FILES

    sources = source_files()
    for relative_name, expected_data in sources.items():
        extracted_path = PROCESSING_DIR / relative_name
        assert extracted_path.is_file(), f"Archive member was not extracted: {relative_name}"
        assert extracted_path.read_bytes() == expected_data, (
            f"Extracted file does not match the source archive: {relative_name}"
        )

    actual_locations = {}
    for path in PROCESSING_DIR.rglob("*chunk*.txt"):
        assert path.is_file()
        relative_name = str(path.relative_to(PROCESSING_DIR))
        actual_locations[relative_name] = path.read_bytes()
    assert actual_locations == expected_locations, (
        "Chunk files in the processing tree are missing, misplaced, extra, or have incorrect contents."
    )

    with tarfile.open(FINAL_ARCHIVE, "r:gz") as tar:
        regular_members = [member for member in tar.getmembers() if member.isfile()]
        assert len(regular_members) == len(tar.getmembers()), (
            "The final archive must contain only flat regular chunk files."
        )
        assert len({member.name for member in regular_members}) == len(regular_members), (
            "The final archive contains duplicate member names."
        )
        actual = {}
        for member in regular_members:
            assert member.name == os.path.basename(member.name), (
                f"Archive member is not flat: {member.name}"
            )
            extracted = tar.extractfile(member)
            assert extracted is not None
            actual[member.name] = extracted.read()

    assert actual == expected, (
        "Archived chunks do not contain the 50-line slices derived from the source log files."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
