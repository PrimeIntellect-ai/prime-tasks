#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tarfile
import tempfile
from pathlib import Path

import pytest

ARCHIVE_PATH = "/home/user/organized_archive.tar.gz"
SOURCE_FILE = "/home/user/organizer.c"
BINARY_FILE = "/home/user/organizer"
LEGACY_DIR = Path("/home/user/legacy_dump")


def test_archive_exists():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} is missing."


def test_archive_contents_and_structure():
    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
                tar.extractall(path=tmpdir)
        except tarfile.TarError as e:
            pytest.fail(f"Failed to extract tarball: {e}")

        base_extracted = os.path.join(tmpdir, "structured")
        assert os.path.isdir(base_extracted), "The archive must contain a 'structured' directory at its root."

        expected_files = {
            "elf/arch_62/controller.elf",
            "elf/arch_40/sensor.elf",
            "gcode/temp_215/chassis.gcode",
            "gcode/temp_190/bracket.gcode",
            "manifest.txt"
        }

        for rel_path in expected_files:
            full_path = os.path.join(base_extracted, rel_path)
            assert os.path.isfile(full_path), f"Expected file missing in archive: structured/{rel_path}"

        # Archived files must be actual copies of the supplied inputs.
        archived_copies = {
            "elf/arch_62/controller.elf": "controller.elf",
            "elf/arch_40/sensor.elf": "sensor.elf",
            "gcode/temp_215/chassis.gcode": "chassis.gcode",
            "gcode/temp_190/bracket.gcode": "bracket.gcode",
        }
        for archived_rel, input_name in archived_copies.items():
            archived_data = Path(base_extracted, archived_rel).read_bytes()
            input_data = (LEGACY_DIR / input_name).read_bytes()
            assert archived_data == input_data, f"Archived file is not an exact copy: structured/{archived_rel}"

        # Verify manifest contents.
        manifest_path = os.path.join(base_extracted, "manifest.txt")
        with open(manifest_path, "r") as f:
            manifest_lines = [line.strip() for line in f.readlines() if line.strip()]

        expected_lines = {
            "controller.elf - ELF - arch 62",
            "sensor.elf - ELF - arch 40",
            "chassis.gcode - GCODE - temp 215",
            "bracket.gcode - GCODE - temp 190"
        }

        actual_lines = set(manifest_lines)
        missing_lines = expected_lines - actual_lines
        assert not missing_lines, f"Manifest is missing expected lines: {missing_lines}"
        assert len(manifest_lines) == len(expected_lines) and actual_lines == expected_lines, \
            "Archived manifest must contain exactly one record for each processed input file."


def test_organizer_binary_and_source_exist():
    assert os.path.isfile(SOURCE_FILE), f"Source file {SOURCE_FILE} is missing."
    assert os.path.isfile(BINARY_FILE), f"Binary file {BINARY_FILE} is missing."
    assert os.access(BINARY_FILE, os.X_OK), f"Binary file {BINARY_FILE} is not executable."
    assert Path(BINARY_FILE).read_bytes()[:4] == b"\x7fELF", "The organizer must be a compiled ELF executable."


def test_atomic_write_rename_used():
    assert os.path.isfile(SOURCE_FILE), "Source file is missing, cannot verify rename() usage."
    with open(SOURCE_FILE, "r") as f:
        source_code = f.read()

    # Retain the source-level requirement and supplement it with runtime tracing below.
    assert "rename(" in source_code.replace(" ", ""), "The C source code does not appear to use the rename() function for atomic writes."


def make_inputs(input_dir, tag):
    input_dir.mkdir()
    arch1 = secrets.randbelow(30000) + 1000
    arch2 = secrets.randbelow(30000) + 35000
    temp1 = secrets.randbelow(70) + 170
    temp2 = secrets.randbelow(70) + 240
    elf1 = f"unit_{tag}_{secrets.token_hex(4)}.elf"
    elf2 = f"module_{tag}_{secrets.token_hex(4)}.elf"
    gc1 = f"part_{tag}_{secrets.token_hex(4)}.gcode"
    gc2 = f"print_{tag}_{secrets.token_hex(4)}.gcode"

    elf1_data = b"\x7fELF" + secrets.token_bytes(12) + struct.pack("<H", 2) + struct.pack("<H", arch1) + secrets.token_bytes(61)
    elf2_data = b"\x7fELF" + secrets.token_bytes(12) + struct.pack("<H", 2) + struct.pack("<H", arch2) + secrets.token_bytes(47)
    gc1_data = f"; generated test\nG28\nM104 S{temp1}\nM104 S{temp2}\nG1 X3 Y7\n".encode()
    gc2_data = f"; another generated test\nG90\nM104 S{temp2}\nG1 X9 Y2\n".encode()

    files = {
        elf1: (elf1_data, f"elf/arch_{arch1}/{elf1}", f"{elf1} - ELF - arch {arch1}"),
        elf2: (elf2_data, f"elf/arch_{arch2}/{elf2}", f"{elf2} - ELF - arch {arch2}"),
        gc1: (gc1_data, f"gcode/temp_{temp1}/{gc1}", f"{gc1} - GCODE - temp {temp1}"),
        gc2: (gc2_data, f"gcode/temp_{temp2}/{gc2}", f"{gc2} - GCODE - temp {temp2}"),
    }
    for name, (data, _, _) in files.items():
        (input_dir / name).write_bytes(data)
    return files


def exercise(executable, root, tag):
    input_dir = root / f"input_{tag}"
    output_dir = root / f"output_{tag}"
    trace_path = root / f"trace_{tag}.txt"
    files = make_inputs(input_dir, tag)

    result = subprocess.run(
        ["strace", "-f", "-e", "trace=rename,renameat,renameat2", "-o", str(trace_path),
         str(executable), str(input_dir), str(output_dir)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, f"Organizer failed on generated inputs: {result.stderr}"
    assert output_dir.is_dir(), "Organizer did not create the requested output directory."

    expected_manifest = set()
    for name, (expected_data, relative_output, manifest_line) in files.items():
        destination = output_dir / relative_output
        assert destination.is_file(), f"Organizer did not create expected output {relative_output}"
        assert destination.read_bytes() == expected_data, f"Organizer did not copy {name} byte-for-byte"
        expected_manifest.add(manifest_line)

    manifest = output_dir / "manifest.txt"
    assert manifest.is_file(), "Organizer did not create manifest.txt"
    lines = [line.strip() for line in manifest.read_text().splitlines() if line.strip()]
    assert len(lines) == len(expected_manifest), "Generated manifest has missing or duplicate records."
    assert set(lines) == expected_manifest, "Generated manifest records do not match the generated inputs."
    assert not (output_dir / "manifest.tmp").exists(), "manifest.tmp was not removed after a successful update."

    trace = trace_path.read_text(errors="replace")
    successful_manifest_renames = [
        line for line in trace.splitlines()
        if "manifest.tmp" in line and "manifest.txt" in line and "= 0" in line
    ]
    assert len(successful_manifest_renames) >= len(files), \
        "The organizer must atomically replace manifest.txt via manifest.tmp for every processed file."


def test_submitted_binary_and_source_work_on_generated_inputs():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)

        # Exercise the submitted executable on unpredictable files and values.
        exercise(Path(BINARY_FILE), root, "submitted")

        # Compile the submitted source independently and exercise that artifact too.
        rebuilt = root / "organizer_rebuilt"
        compile_result = subprocess.run(
            ["gcc", SOURCE_FILE, "-o", str(rebuilt)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compile_result.returncode == 0, f"organizer.c does not compile: {compile_result.stderr}"
        exercise(rebuilt, root, "rebuilt")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
