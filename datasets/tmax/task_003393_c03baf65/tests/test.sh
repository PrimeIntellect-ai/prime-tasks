#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import subprocess
from datetime import datetime

import pytest

MERGED_FILE = "/home/user/merged_print.gcode"
REPORT_FILE = "/home/user/report.json"
WAL_FILE = "/home/user/config_manager.wal"
PART_PATTERN = "/home/user/gcode_parts/print.gcode.part*"


def decode_part(data):
    if data.startswith(b"\xef\xbb\xbf"):
        return data.decode("utf-8-sig")
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    if len(data) >= 2:
        even_nuls = data[0::2].count(0)
        odd_nuls = data[1::2].count(0)
        if odd_nuls > len(data[1::2]) // 3 and even_nuls == 0:
            return data.decode("utf-16le")
        if even_nuls > len(data[0::2]) // 3 and odd_nuls == 0:
            return data.decode("utf-16be")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("windows-1252")


def expected_merged_text():
    numbered = []
    for path in glob.glob(PART_PATTERN):
        match = re.fullmatch(r"print\.gcode\.part(\d+)", os.path.basename(path))
        assert match, f"Unexpected GCode fragment name: {path}"
        numbered.append((int(match.group(1)), path))
    assert numbered, "No GCode fragments were found."
    assert len({number for number, _ in numbered}) == len(numbered), "Duplicate fragment numbers found."

    chunks = []
    for _, path in sorted(numbered):
        with open(path, "rb") as f:
            chunks.append(decode_part(f.read()))
    return "".join(chunks)


def calculate_extrusion(text):
    total = 0.0
    number = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
    e_parameter = re.compile(rf"(?:^|\s)E({number})(?=\s|$)", re.IGNORECASE)
    for raw_line in text.splitlines():
        line = raw_line.split(";", 1)[0].strip()
        if not re.match(r"^G1(?:\s|$)", line, re.IGNORECASE):
            continue
        for match in e_parameter.finditer(line):
            total += float(match.group(1))
    return total


def latest_successful_firmware():
    entries = []
    with open(WAL_FILE, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            fields = [field.strip() for field in line.strip().split("|")]
            assert len(fields) == 4, f"Malformed WAL line {line_number}"
            timestamp_text, action, filepath, status = fields
            assert timestamp_text.startswith("[") and timestamp_text.endswith("]"), \
                f"Malformed timestamp on WAL line {line_number}"
            timestamp = datetime.fromisoformat(timestamp_text[1:-1])
            if action == "FIRMWARE_UPDATE" and status == "SUCCESS":
                entries.append((timestamp, filepath))
    assert entries, "No successful firmware update exists in the WAL."
    return max(entries, key=lambda item: item[0])[1]


def get_expected_entry_point(filepath):
    try:
        result = subprocess.run(
            ["readelf", "-h", filepath], capture_output=True, text=True, check=True
        )
        for line in result.stdout.splitlines():
            if "Entry point address:" in line:
                return line.split(":", 1)[1].strip()
    except Exception as e:
        pytest.fail(f"Failed to run readelf to determine expected entry point: {e}")
    return None


def test_merged_gcode_exists_and_is_correct_utf8():
    assert os.path.isfile(MERGED_FILE), f"The merged GCode file {MERGED_FILE} does not exist."

    expected_text = expected_merged_text()
    with open(MERGED_FILE, "rb") as f:
        actual_bytes = f.read()

    try:
        actual_text = actual_bytes.decode("utf-8")
    except UnicodeDecodeError as e:
        pytest.fail(f"The merged GCode file is not valid UTF-8: {e}")

    assert actual_bytes == expected_text.encode("utf-8"), \
        "The merged GCode does not contain all decoded fragments in numerical order."
    assert actual_text == expected_text


def test_report_exists():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."


def test_report_contents():
    with open(REPORT_FILE, "r", encoding="utf-8") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_FILE} does not contain valid JSON.")

    expected_firmware_path = "/home/user/firmwares/v2.elf"
    expected_total_extrusion = 12.0

    assert "latest_firmware_path" in report, "Key 'latest_firmware_path' is missing from report.json."
    assert report["latest_firmware_path"] == expected_firmware_path, \
        f"Expected latest_firmware_path to be '{expected_firmware_path}', but got '{report['latest_firmware_path']}'."

    derived_firmware_path = latest_successful_firmware()
    assert report["latest_firmware_path"] == derived_firmware_path, \
        "latest_firmware_path does not match the latest successful FIRMWARE_UPDATE in the WAL."

    assert "total_extrusion" in report, "Key 'total_extrusion' is missing from report.json."
    assert isinstance(report["total_extrusion"], (int, float)), \
        "Value for 'total_extrusion' must be a number."
    assert abs(report["total_extrusion"] - expected_total_extrusion) < 1e-5, \
        f"Expected total_extrusion to be {expected_total_extrusion}, but got {report['total_extrusion']}."

    with open(MERGED_FILE, "r", encoding="utf-8") as f:
        derived_total = calculate_extrusion(f.read())
    assert abs(report["total_extrusion"] - derived_total) < 1e-5, \
        "total_extrusion does not equal the E values parsed from G1 commands in the merged file."

    assert "firmware_entry_point" in report, "Key 'firmware_entry_point' is missing from report.json."
    assert os.path.isfile(derived_firmware_path), "The firmware selected from the WAL is not a file."
    expected_entry_point = get_expected_entry_point(derived_firmware_path)
    assert expected_entry_point is not None, "Could not determine the expected entry point from the ELF file."
    assert isinstance(report["firmware_entry_point"], str), \
        "Value for 'firmware_entry_point' must be a string."
    assert report["firmware_entry_point"].lower() == expected_entry_point.lower(), \
        f"Expected firmware_entry_point to be '{expected_entry_point}', but got '{report['firmware_entry_point']}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
