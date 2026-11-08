#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import tarfile
import zipfile
from pathlib import PurePosixPath

import pytest

ARCHIVE_PATH = "/home/user/raw_projects.tar.gz"
SUMMARY_PATH = "/home/user/summary.json"
ZIP_PATH = "/home/user/valid_gcodes.zip"


def derive_expected():
    """Derive valid jobs, durations, and exact GCode bytes from the input archive."""
    assert os.path.isfile(ARCHIVE_PATH), f"The source archive {ARCHIVE_PATH} is missing."

    jobs = {}
    with tarfile.open(ARCHIVE_PATH, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue

            path = PurePosixPath(member.name)
            if path.name not in {"model.gcode", "print_server.log"}:
                continue

            extracted = archive.extractfile(member)
            assert extracted is not None, f"Could not read {member.name} from the archive."
            job_name = path.parent.name
            assert job_name, f"Could not determine the job directory for {member.name}."
            assert path.name not in jobs.setdefault(job_name, {}), (
                f"Duplicate {path.name} found for job {job_name}."
            )
            jobs[job_name][path.name] = extracted.read()

    expected_summary = {}
    expected_gcodes = {}

    for job_name, files in jobs.items():
        if set(files) != {"model.gcode", "print_server.log"}:
            continue

        try:
            gcode_text = files["model.gcode"].decode("utf-8")
            log_text = files["print_server.log"].decode("utf-8")
        except UnicodeDecodeError as exc:
            pytest.fail(f"Job {job_name} contains a non-UTF-8 input file: {exc}")

        layer_counts = []
        for line in gcode_text.splitlines():
            match = re.fullmatch(r"; LAYER_COUNT: ([0-9]+)", line)
            if match:
                layer_counts.append(int(match.group(1)))

        log_lines = log_text.splitlines()
        successful = any(line.endswith("STATUS: SUCCESS") for line in log_lines)
        has_error = any("[ERROR]" in line for line in log_lines)
        durations = []
        for line in log_lines:
            match = re.fullmatch(r"Duration: (.+)", line)
            if match:
                durations.append(match.group(1))

        if any(count > 100 for count in layer_counts) and successful and not has_error and durations:
            expected_summary[job_name] = durations[0]
            expected_gcodes[f"{job_name}_model.gcode"] = files["model.gcode"]

    return expected_summary, expected_gcodes


EXPECTED_SUMMARY, EXPECTED_GCODES = derive_expected()


def test_summary_json_exists_and_correct():
    """Test that summary.json exists and contains the archive-derived mapping."""
    assert os.path.exists(SUMMARY_PATH), f"The file {SUMMARY_PATH} is missing."
    assert os.path.isfile(SUMMARY_PATH), f"{SUMMARY_PATH} should be a file."

    with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {SUMMARY_PATH} does not contain valid JSON.")

    assert data == EXPECTED_SUMMARY, (
        f"The contents of {SUMMARY_PATH} are incorrect. "
        f"Expected {EXPECTED_SUMMARY}, but got {data}."
    )


def test_valid_gcodes_zip_exists_and_correct():
    """Test ZIP names and verify every member is the exact source GCode file."""
    assert os.path.exists(ZIP_PATH), f"The file {ZIP_PATH} is missing."
    assert os.path.isfile(ZIP_PATH), f"{ZIP_PATH} should be a file."
    assert zipfile.is_zipfile(ZIP_PATH), f"{ZIP_PATH} is not a valid zip archive."

    with zipfile.ZipFile(ZIP_PATH, "r") as archive:
        names = archive.namelist()
        zip_contents = set(names)
        expected_names = set(EXPECTED_GCODES)

        assert zip_contents == expected_names, (
            f"The zip archive {ZIP_PATH} contains incorrect files. "
            f"Expected {expected_names}, but got {zip_contents}."
        )
        assert len(names) == len(expected_names), (
            f"The zip archive {ZIP_PATH} contains duplicate members."
        )
        assert all(PurePosixPath(name).name == name for name in names), (
            "ZIP members must be files at the archive root."
        )

        for filename, expected_content in EXPECTED_GCODES.items():
            actual_content = archive.read(filename)
            assert actual_content == expected_content, (
                f"The file {filename} inside the ZIP is not byte-for-byte identical "
                "to its source model.gcode in the input archive."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
