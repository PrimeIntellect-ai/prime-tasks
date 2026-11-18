#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import shutil
import subprocess
import tarfile

import pytest

SCRIPT_PATH = "/home/user/optimize_logs.sh"
SPOOL_PATH = "/home/user/incoming/spool.tar"
ARCHIVE_PATH = "/home/user/processed/final_archive.tar.xz"


def parse_records(text):
    rows = []
    current = None

    for line in text.splitlines():
        if line.strip() == "=== RECORD START ===":
            current = []
        elif line.strip() == "=== RECORD END ===":
            if current is not None:
                timestamp = None
                severity = None
                message = None

                for index, record_line in enumerate(current):
                    if record_line.startswith("Timestamp:"):
                        timestamp = record_line.split(":", 1)[1].strip()
                    elif record_line.startswith("Severity:"):
                        severity = record_line.split(":", 1)[1].strip()
                    elif record_line.startswith("Message:"):
                        inline = record_line.split(":", 1)[1].strip()
                        if inline:
                            message = inline
                        elif index + 1 < len(current):
                            message = current[index + 1].strip()

                assert timestamp is not None, "A source record has no Timestamp field."
                assert severity is not None, "A source record has no Severity field."
                assert message is not None, "A source record has no first Message line."
                rows.append([timestamp, severity, message])
            current = None
        elif current is not None:
            current.append(line)

    return rows


def rows_from_tar(fileobj):
    rows = []
    with tarfile.open(fileobj=fileobj, mode="r:*") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            extracted = archive.extractfile(member)
            assert extracted is not None
            payload = extracted.read()

            # Recursively process any archives stored inside the outer spool.
            try:
                rows.extend(rows_from_tar(io.BytesIO(payload)))
                continue
            except tarfile.ReadError:
                pass

            try:
                text = payload.decode("utf-8")
            except UnicodeDecodeError:
                continue
            rows.extend(parse_records(text))
    return rows


@pytest.fixture(scope="session", autouse=True)
def generated_archive():
    assert os.path.exists(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."
    assert os.path.isfile(SPOOL_PATH), f"The source archive {SPOOL_PATH} does not exist."

    with open(SPOOL_PATH, "rb") as source:
        expected_rows = rows_from_tar(source)
    assert len(expected_rows) == 5000, f"Expected 5000 records in spool.tar, found {len(expected_rows)}."

    # Require the submitted script to generate a fresh result during verification.
    if os.path.lexists(ARCHIVE_PATH):
        if os.path.isdir(ARCHIVE_PATH) and not os.path.islink(ARCHIVE_PATH):
            shutil.rmtree(ARCHIVE_PATH)
        else:
            os.unlink(ARCHIVE_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return expected_rows


def test_final_archive_exists_and_size(generated_archive):
    assert os.path.exists(ARCHIVE_PATH), f"The file {ARCHIVE_PATH} does not exist."
    assert os.path.isfile(ARCHIVE_PATH), f"The path {ARCHIVE_PATH} is not a file."

    size = os.path.getsize(ARCHIVE_PATH)
    assert size <= 25000, f"Archive size is {size} bytes, which exceeds the threshold of 25000 bytes. The bloat was not properly removed or compression was insufficient."


def test_final_archive_contents(generated_archive):
    assert os.path.exists(ARCHIVE_PATH), f"The file {ARCHIVE_PATH} does not exist."

    extract_dir = "/tmp/verifier_extract"
    shutil.rmtree(extract_dir, ignore_errors=True)
    os.makedirs(extract_dir)

    result = subprocess.run(
        ["tar", "-xf", ARCHIVE_PATH, "-C", extract_dir],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to extract {ARCHIVE_PATH}. Is it a valid tar.xz archive? Error: {result.stderr}"

    csv_path = os.path.join(extract_dir, "summary.csv")
    assert os.path.exists(csv_path), "summary.csv was not found inside the extracted archive."
    assert os.path.isfile(csv_path), "summary.csv inside the archive is not a regular file."

    with open(csv_path, "r", encoding="utf-8", newline="") as csv_file:
        raw_lines = csv_file.readlines()

    assert len(raw_lines) == 5001, f"Expected exactly 5001 lines in summary.csv (5000 records + 1 header), but got {len(raw_lines)}."
    assert raw_lines[0].strip() == "Time,Level,Error", f"Expected header 'Time,Level,Error', but got '{raw_lines[0].strip()}'."

    with open(csv_path, "r", encoding="utf-8", newline="") as csv_file:
        parsed_rows = list(csv.reader(csv_file))

    assert parsed_rows[0] == ["Time", "Level", "Error"], "summary.csv does not have the required strict CSV header."
    assert parsed_rows[1:] == generated_archive, "The CSV data rows do not match the Timestamp, Severity, and first Message line from spool.tar."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
