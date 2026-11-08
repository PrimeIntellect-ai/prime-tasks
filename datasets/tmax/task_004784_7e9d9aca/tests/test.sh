#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import zlib

import pytest


def get_elf_entry_point(filepath):
    """Uses readelf to find the entry point address of an ELF file."""
    result = subprocess.run(
        ["readelf", "-h", filepath],
        capture_output=True,
        text=True,
        check=True
    )
    for line in result.stdout.splitlines():
        if "Entry point address:" in line:
            parts = line.split(":")
            if len(parts) == 2:
                return parts[1].strip().lower()
    raise ValueError(f"Could not find entry point in {filepath}")


def test_final_summary_exists_and_correct():
    zlib_path = "/home/user/final_summary.zlib"
    assert os.path.isfile(zlib_path), f"File {zlib_path} is missing."

    with open(zlib_path, "rb") as f:
        compressed_data = f.read()

    try:
        decompressed_data = zlib.decompress(compressed_data).decode("utf-8")
    except Exception as e:
        pytest.fail(f"Failed to decompress and decode {zlib_path}: {e}")

    fw1_entry = get_elf_entry_point("/home/user/project_files/firmware/fw1.elf")
    fw2_entry = get_elf_entry_point("/home/user/project_files/firmware/fw2.elf")

    expected_output = f"""[part1.gcode]
G0 X10 Y10 Z5 F1000 °C
G1 X15 Y15 Z0 F500
G1 X20 Y15 Z0
[part2.gcode]
G0 Z10
G0 X0 Y0
G1 Z-1 F100

fw1.elf: {fw1_entry}
fw2.elf: {fw2_entry}
"""

    assert decompressed_data.strip() == expected_output.strip(), (
        "Decompressed content does not match the expected output.\n"
        f"Expected:\n{expected_output}\n"
        f"Got:\n{decompressed_data}"
    )


def test_intermediate_files_exist():
    gcode_summary = "/home/user/gcode_summary.txt"
    elf_summary = "/home/user/elf_summary.txt"

    assert os.path.isfile(gcode_summary), f"File {gcode_summary} is missing."
    assert os.path.isfile(elf_summary), f"File {elf_summary} is missing."

    with open(gcode_summary, "r", encoding="utf-8") as f:
        gcode_content = f.read()

    assert "[part1.gcode]" in gcode_content, "gcode_summary.txt missing part1.gcode data"
    assert "G0 X10 Y10 Z5 F1000 °C" in gcode_content, "gcode_summary.txt missing UTF-8 decoded content"


def test_program_builds_and_handles_unseen_recursive_fixture():
    source = "/home/user/organizer.go"
    assert os.path.isfile(source), f"Go source {source} is missing."

    executable = "/tmp/organizer_under_test"
    build = subprocess.run(
        ["go", "build", "-o", executable, source],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"organizer.go failed to build:\n{build.stderr}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)

    # Preserve two valid, independently parsed ELF payloads before replacing the
    # fixed project tree with unpredictable nested input names.
    original_elfs = [
        "/home/user/project_files/firmware/fw1.elf",
        "/home/user/project_files/firmware/fw2.elf",
    ]
    elf_payloads = []
    for path in original_elfs:
        with open(path, "rb") as f:
            elf_payloads.append(f.read())

    token = secrets.token_hex(6)
    project = "/home/user/project_files"
    shutil.rmtree(project)
    os.makedirs(os.path.join(project, "deep", "gcodes"))
    os.makedirs(os.path.join(project, "other", "firmware", "nested"))

    gcode_inputs = {
        f"a_{token}.gcode": [
            "; ignored préface",
            "G0 X7 Y8 température °C",
            "M3",
            "G1 X9 Y10 F321",
            "G0 Z4",
            "G1 X999 ; fourth movement is ignored",
        ],
        f"z_{token}.gcode": [
            "G1 X-1 Y-2",
            "; commentaire café",
            "G0 Z12",
            "G1 X3 Y4",
            "G0 X100 ; fourth movement is ignored",
        ],
    }
    gcode_locations = [
        os.path.join(project, "deep", "gcodes"),
        os.path.join(project, "other"),
    ]
    for (name, lines), directory in zip(gcode_inputs.items(), gcode_locations):
        with open(os.path.join(directory, name), "wb") as f:
            f.write(("\n".join(lines) + "\n").encode("iso-8859-1"))

    elf_names = [f"m_{token}.elf", f"b_{token}.elf"]
    elf_paths = [
        os.path.join(project, "other", "firmware", elf_names[0]),
        os.path.join(project, "other", "firmware", "nested", elf_names[1]),
    ]
    for path, payload in zip(elf_paths, elf_payloads):
        with open(path, "wb") as f:
            f.write(payload)

    # Noise must not be included.
    with open(os.path.join(project, "deep", "ignore.txt"), "w", encoding="utf-8") as f:
        f.write("G0 SHOULD NOT APPEAR\n")

    for output in (
        "/home/user/gcode_summary.txt",
        "/home/user/elf_summary.txt",
        "/home/user/final_summary.zlib",
    ):
        if os.path.lexists(output):
            os.unlink(output)

    run = subprocess.run(
        [executable],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert run.returncode == 0, f"Built organizer failed to run:\n{run.stderr}"

    expected_gcode_blocks = []
    for name in sorted(gcode_inputs):
        movements = [line for line in gcode_inputs[name] if line.startswith(("G0", "G1"))][:3]
        expected_gcode_blocks.append("\n".join([f"[{name}]"] + movements))
    expected_gcode = "\n".join(expected_gcode_blocks)

    elf_entries = {
        name: get_elf_entry_point(path)
        for name, path in zip(elf_names, elf_paths)
    }
    expected_elf = "\n".join(
        f"{name}: {elf_entries[name]}" for name in sorted(elf_entries)
    )
    expected_merged = expected_gcode + "\n\n" + expected_elf

    with open("/home/user/gcode_summary.txt", "r", encoding="utf-8") as f:
        actual_gcode = f.read()
    with open("/home/user/elf_summary.txt", "r", encoding="utf-8") as f:
        actual_elf = f.read()
    assert actual_gcode.strip() == expected_gcode.strip()
    assert actual_elf.strip() == expected_elf.strip()

    with open("/home/user/final_summary.zlib", "rb") as f:
        compressed = f.read()
    try:
        actual_merged = zlib.decompress(compressed).decode("utf-8")
    except Exception as e:
        pytest.fail(f"Generated final_summary.zlib is not valid UTF-8 zlib data: {e}")
    assert actual_merged.strip() == expected_merged.strip()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
