#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

import pytest

SCRIPT_PATH = "/home/user/parse_artifacts.py"
JSON_PATH = "/home/user/curated_artifacts.json"
LOG_DIR = Path("/home/user/logs")
LOG_PATHS = [
    LOG_DIR / "build.log.2",
    LOG_DIR / "build.log.1",
    LOG_DIR / "build.log",
]


def test_script_exists():
    """Test that the python script was created."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist. Did you create it?"


def test_json_output_exists():
    """Test that the curated_artifacts.json file was created."""
    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} does not exist. Did you run your script?"


def test_json_output_content():
    """Test that the curated_artifacts.json file contains the correct parsed metadata."""
    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} does not exist."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")

    expected_data = {
        "001": {
            "type": "GCODE",
            "max_z": 12.4
        },
        "002": {
            "type": "ELF",
            "entry_point": "0x8048100"
        },
        "003": {
            "type": "GCODE",
            "max_z": 1.1
        }
    }

    assert isinstance(data, dict), f"Expected the JSON root to be a dictionary, got {type(data).__name__}"

    for key, expected_val in expected_data.items():
        assert key in data, f"Missing artifact ID '{key}' in JSON output."
        assert data[key] == expected_val, f"Incorrect data for artifact '{key}'. Expected {expected_val}, got {data[key]}"

    extra_keys = set(data.keys()) - set(expected_data.keys())
    assert not extra_keys, f"Found unexpected artifact IDs in JSON output: {extra_keys}"


def test_script_functionally_parses_rotated_logs():
    """Execute the submitted parser against fresh records split across rotations."""
    ids = set()
    while len(ids) < 3:
        ids.add(f"{secrets.randbelow(900000) + 100000:06d}")
    gcode_id, elf_id, second_gcode_id = sorted(ids)

    seed = secrets.randbelow(500) + 100
    low_z = -(secrets.randbelow(90) + 1) / 10.0
    middle_z = seed / 10.0
    max_z = (seed + 137) / 10.0
    decoy_z = max_z + 500.0
    second_low = -(secrets.randbelow(100) + 10) / 10.0
    second_max = (secrets.randbelow(400) + 10) / 10.0
    entry_point = f"0x{secrets.randbits(48):012x}"

    record_one = (
        f"[RECORD_START] ID: {gcode_id}\n"
        "TYPE: GCODE\n"
        "DATA:\n"
        f"G1 X4 Z{low_z:.1f} Y8\n"
        f"G0 X2 Z{middle_z:.1f}\n"
        f"G2 Z{decoy_z:.1f}\n"
        f"G1 X9 Z{max_z:.1f} Y3\n"
        "[RECORD_END]\n"
    )
    record_two = (
        f"[RECORD_START] ID: {elf_id}\n"
        "TYPE: ELF\n"
        "DATA:\n"
        "Magic: 7f 45 4c 46\n"
        f"Entry point address:               {entry_point}\n"
        "Start of program headers:          64 (bytes into file)\n"
        "[RECORD_END]\n"
    )
    record_three = (
        f"[RECORD_START] ID: {second_gcode_id}\n"
        "TYPE: GCODE\n"
        "DATA:\n"
        f"G1 Z{second_low:.1f}\n"
        f"G0 X1 Y2 Z{second_max:.1f}\n"
        "[RECORD_END]\n"
    )
    stream = record_one + record_two + record_three

    max_token = f"Z{max_z:.1f}"
    first_cut = stream.index(max_token) + 2
    entry_value_start = stream.index(entry_point)
    second_cut = entry_value_start + min(5, len(entry_point) - 1)
    assert first_cut < second_cut

    replacements = [
        stream[:first_cut],
        stream[first_cut:second_cut],
        stream[second_cut:],
    ]
    expected = {
        gcode_id: {"type": "GCODE", "max_z": max_z},
        elf_id: {"type": "ELF", "entry_point": entry_point},
        second_gcode_id: {"type": "GCODE", "max_z": second_max},
    }

    original_logs = {path: path.read_bytes() for path in LOG_PATHS}
    output_path = Path(JSON_PATH)
    original_output = output_path.read_bytes() if output_path.exists() else None

    try:
        for path, content in zip(LOG_PATHS, replacements):
            path.write_text(content, encoding="utf-8")
        if output_path.exists():
            output_path.unlink()

        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Parser exited with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert output_path.is_file(), "Executing the parser did not create curated_artifacts.json"

        try:
            with output_path.open("r", encoding="utf-8") as f:
                actual = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Parser generated invalid JSON: {exc}")

        assert actual == expected, f"Parser produced {actual}, expected {expected}"
    finally:
        for path, content in original_logs.items():
            path.write_bytes(content)
        if original_output is None:
            if output_path.exists():
                output_path.unlink()
        else:
            output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
