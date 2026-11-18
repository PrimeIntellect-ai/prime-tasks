#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import struct
import subprocess
import secrets
import pytest

PROJECT_DATA_DIR = "/home/user/project_data"
REPORT_PATH = "/home/user/backup_report.json"
SCRIPT_PATH = "/home/user/archiver.py"

@pytest.fixture(scope="session", autouse=True)
def execute_archiver():
    assert os.path.isfile(SCRIPT_PATH), f"Required Python script not found at {SCRIPT_PATH}"

    # Add inputs unknown at image-build/agent time so precomputed outputs cannot pass.
    token = secrets.token_hex(8)
    fixture_dir = os.path.join(PROJECT_DATA_DIR, f"verification_{token}", "nested")
    os.makedirs(fixture_dir, exist_ok=True)

    first = secrets.randbelow(80) / 10 + 0.1
    second = secrets.randbelow(80) / 10 + 0.1
    gcode_path = os.path.join(fixture_dir, f"part_{token}.gcode")
    with open(gcode_path, "w", encoding="utf-8") as f:
        f.write(f"G0 X0 Y0\nG1 X1 Y2 E{first}\nG1 X3 Y4 E{second}\nM117 G0 marker\n")

    entry_point = secrets.randbits(48) | 1
    elf_header = bytearray(32)
    elf_header[0:4] = b"\x7fELF"
    elf_header[4] = 2
    elf_header[5] = 1
    elf_header[6] = 1
    struct.pack_into("<Q", elf_header, 24, entry_point)
    with open(os.path.join(fixture_dir, f"firmware_{token}.elf"), "wb") as f:
        f.write(elf_header)

    # Require this execution to regenerate every demanded artifact.
    if os.path.lexists(REPORT_PATH):
        if os.path.isdir(REPORT_PATH) and not os.path.islink(REPORT_PATH):
            import shutil
            shutil.rmtree(REPORT_PATH)
        else:
            os.unlink(REPORT_PATH)

    compressed_paths = []
    for root, dirs, files in os.walk(PROJECT_DATA_DIR):
        for name in files:
            if name.endswith(".gcode.cz"):
                compressed_paths.append(os.path.join(root, name))
    for path in compressed_paths:
        os.unlink(path)

    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("archiver.py did not finish within 60 seconds")

    assert result.returncode == 0, (
        f"archiver.py exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def get_expected_entry_point(filepath):
    with open(filepath, "rb") as f:
        header = f.read(32)
        if len(header) < 32:
            return None
        # Check if 32-bit or 64-bit
        is_64_bit = header[4] == 2
        endian = "<" if header[5] == 1 else ">"

        if is_64_bit:
            entry_point = struct.unpack_from(endian + "Q", header, 24)[0]
        else:
            entry_point = struct.unpack_from(endian + "I", header, 24)[0]

        return hex(entry_point)


def get_expected_extrusion(filepath):
    total = 0.0
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("G1 "):
                parts = line.split()
                for part in parts:
                    if part.startswith("E"):
                        try:
                            total += float(part[1:])
                        except ValueError:
                            pass
    return round(total, 2)


def get_expected_compressed_bytes(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    # The requirement says:
    # Replace every occurrence of the string "G0 " with the byte \x01.
    # Replace every occurrence of the string "G1 " with the byte \x02.
    # Write the resulting byte sequence to the .cz file, prepended with the magic header bytes CZMA (in ASCII).

    encoded = content.encode("utf-8")
    encoded = encoded.replace(b"G0 ", b"\x01")
    encoded = encoded.replace(b"G1 ", b"\x02")

    return b"CZMA" + encoded


def test_backup_report_exists_and_correct():
    assert os.path.exists(REPORT_PATH), f"Report file not found at {REPORT_PATH}"

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Backup report is not valid JSON")

    assert isinstance(report_data, list), "Report data should be a list of objects"

    # Compute expected report
    expected_report = []
    for root, _, files in os.walk(PROJECT_DATA_DIR):
        for file in files:
            filepath = os.path.join(root, file)
            rel_path = os.path.relpath(filepath, PROJECT_DATA_DIR)

            if file.endswith(".elf"):
                entry_point = get_expected_entry_point(filepath)
                expected_report.append({
                    "file": rel_path,
                    "type": "elf",
                    "metadata": {
                        "entry_point": entry_point
                    }
                })
            elif file.endswith(".gcode"):
                extrusion = get_expected_extrusion(filepath)
                expected_report.append({
                    "file": rel_path,
                    "type": "gcode",
                    "metadata": {
                        "total_extrusion": extrusion
                    }
                })

    expected_report.sort(key=lambda x: x["file"])

    assert len(report_data) == len(expected_report), f"Expected {len(expected_report)} entries, got {len(report_data)}"

    for actual, expected in zip(report_data, expected_report):
        assert actual.get("file") == expected["file"], f"Expected file path {expected['file']}, got {actual.get('file')}"
        assert actual.get("type") == expected["type"], f"Expected type {expected['type']} for {expected['file']}"
        assert "metadata" in actual, f"Missing metadata for {expected['file']}"

        if expected["type"] == "elf":
            assert actual["metadata"].get("entry_point") == expected["metadata"]["entry_point"], \
                f"Incorrect entry_point for {expected['file']}"
        elif expected["type"] == "gcode":
            assert actual["metadata"].get("total_extrusion") == expected["metadata"]["total_extrusion"], \
                f"Incorrect total_extrusion for {expected['file']}"


def test_custom_compression_files():
    for root, _, files in os.walk(PROJECT_DATA_DIR):
        for file in files:
            if file.endswith(".gcode"):
                original_path = os.path.join(root, file)
                compressed_path = original_path + ".cz"

                assert os.path.exists(compressed_path), f"Compressed file missing: {compressed_path}"

                expected_bytes = get_expected_compressed_bytes(original_path)

                with open(compressed_path, "rb") as f:
                    actual_bytes = f.read()

                assert actual_bytes == expected_bytes, f"Compressed content mismatch in {compressed_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
