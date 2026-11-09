#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import struct
import subprocess
import tempfile
import uuid
import zipfile
import pytest

HOME = "/home/user"
PROJECT = os.path.join(HOME, "project_files")


def test_extracted_files():
    """Test that every intact archive member was extracted exactly."""
    archive = os.path.join(HOME, "project_backup.zip")
    assert os.path.isfile(archive), f"Missing {archive}"
    assert os.path.isdir(PROJECT), f"Directory {PROJECT} does not exist."

    with zipfile.ZipFile(archive, "r") as zf:
        assert zf.testzip() is None, "The ZIP archive contains a member with a bad CRC."
        members = [i for i in zf.infolist() if not i.is_dir()]
        assert members, "The ZIP archive contains no files."
        for info in members:
            normalized = os.path.normpath(info.filename)
            assert not os.path.isabs(normalized) and normalized != ".." and not normalized.startswith(".." + os.sep)
            extracted = os.path.join(PROJECT, normalized)
            assert os.path.isfile(extracted), f"Expected extracted file {extracted} is missing."
            with open(extracted, "rb") as f:
                actual = f.read()
            assert actual == zf.read(info), f"Extracted file {extracted} differs from the archive member."

    expected_files = ["compiler_output.log", "firmware.elf", "main_print.gcode"]
    for name in expected_files:
        path = os.path.join(PROJECT, name)
        assert os.path.isfile(path), f"Expected extracted file {path} is missing."


def test_program_artifacts():
    source = os.path.join(HOME, "organize.c")
    program = os.path.join(HOME, "organize")
    assert os.path.isfile(source), f"Missing C source {source}"
    assert os.path.isfile(program), f"Missing compiled program {program}"
    assert os.access(program, os.X_OK), f"{program} is not executable"
    with open(program, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{program} is not a compiled ELF program"

    with open(source, "r", encoding="utf-8", errors="replace") as f:
        source_text = f.read()
    string_literals = re.findall(r'"(?:\\.|[^"\\])*"', source_text)
    assert not any("readelf" in literal.lower() for literal in string_literals), \
        "The C program must parse the ELF header directly rather than invoke readelf."


def test_entry_point():
    """Test that the entry point in /home/user/entry_point.txt matches the ELF file."""
    elf_path = os.path.join(PROJECT, "firmware.elf")
    txt_path = os.path.join(HOME, "entry_point.txt")

    assert os.path.isfile(elf_path), f"Missing {elf_path}"
    assert os.path.isfile(txt_path), f"Missing {txt_path}"

    with open(elf_path, "rb") as f:
        e_ident = f.read(16)
        assert e_ident[:4] == b"\x7fELF", f"{elf_path} is not a valid ELF file."
        is_64_bit = e_ident[4] == 2
        endianness = "<" if e_ident[5] == 1 else ">"
        if is_64_bit:
            f.seek(24)
            entry_point = struct.unpack(endianness + "Q", f.read(8))[0]
        else:
            f.seek(24)
            entry_point = struct.unpack(endianness + "I", f.read(4))[0]

    with open(txt_path, "r") as f:
        actual_entry_str = f.read().strip()
    try:
        actual_entry = int(actual_entry_str, 16)
    except ValueError:
        pytest.fail(f"Could not parse entry point from {txt_path} as hex: {actual_entry_str}")
    assert entry_point == actual_entry, f"Entry point mismatch. Expected {hex(entry_point)}, got {hex(actual_entry)}"


def test_gcode_chunks():
    """Retain the original checks for the supplied GCode file."""
    chunks_dir = os.path.join(HOME, "gcode_chunks")
    assert os.path.isdir(chunks_dir), f"Directory {chunks_dir} does not exist."
    paths = [os.path.join(chunks_dir, f"chunk_{i:02d}.gcode") for i in range(4)]
    for path in paths:
        assert os.path.isfile(path), f"Missing {path}"

    with open(paths[0], "r") as f:
        lines0 = f.read().splitlines()
    assert len(lines0) == 4, f"{paths[0]} should have 4 lines."
    assert "M104 S200" in lines0, f"Missing expected content in {paths[0]}"

    with open(paths[1], "r") as f:
        lines1 = f.read().splitlines()
    assert len(lines1) == 3, f"{paths[1]} should have 3 lines."
    assert lines1[0] == ";LAYER_CHANGE", f"{paths[1]} should start with ;LAYER_CHANGE"
    assert "G1 X20 Y10 F3000" in lines1, f"Missing expected content in {paths[1]}"

    with open(paths[2], "r") as f:
        lines2 = f.read().splitlines()
    assert len(lines2) == 3, f"{paths[2]} should have 3 lines."
    assert lines2[0] == ";LAYER_CHANGE", f"{paths[2]} should start with ;LAYER_CHANGE"

    with open(paths[3], "r") as f:
        lines3 = f.read().splitlines()
    assert len(lines3) == 4, f"{paths[3]} should have 4 lines."
    assert lines3[0] == ";LAYER_CHANGE", f"{paths[3]} should start with ;LAYER_CHANGE"
    assert "M140 S0" in lines3, f"Missing expected content in {paths[3]}"


def make_elf64(path, entry):
    ident = b"\x7fELF" + bytes([2, 1, 1, 0, 0]) + b"\0" * 7
    header = struct.pack(
        "<16sHHIQQQIHHHHHH",
        ident, 2, 62, 1, entry, 0, 0, 0, 64, 56, 0, 64, 0, 0
    )
    with open(path, "wb") as f:
        f.write(header)
        f.write(os.urandom(127))


def expected_chunks(lines):
    chunks = [[]]
    for line in lines:
        if line.startswith(";LAYER_CHANGE"):
            chunks.append([])
        chunks[-1].append(line)
    return ["".join(chunk).encode() for chunk in chunks]


def exercise(program):
    token = uuid.uuid4().hex
    entry = 0x400000 + int(token[:6], 16)
    target = os.path.join(PROJECT, f"firmware_{token}.elf")
    make_elf64(target, entry)

    log = (
        "---\n"
        "[INFO] decoy path /tmp/not_the_target.elf\n"
        "[WARN] continuing build\n"
        "---\n"
        "[ERROR] generated output is unusable\n"
        f"FATAL ERROR: Corrupted binary generated: {target}\n"
        "diagnostic continuation line one\n"
        "diagnostic continuation line two\n"
        "---\n"
        "[INFO] final block\n"
        "---\n"
    )
    with open(os.path.join(PROJECT, "compiler_output.log"), "w") as f:
        f.write(log)

    lines = [
        f"G1 X{token[:4]} Y1\n",
        "M104 S211\n",
        ";LAYER_CHANGE\n",
        f"G1 X2 Y{token[4:8]}\n",
        "G0 Z0.25\n",
        ";LAYER_CHANGE\n",
        "G1 X30 Y40\n",
        ";LAYER_CHANGE\n",
        f"M117 {token}\n",
        "M104 S0\n",
    ]
    with open(os.path.join(PROJECT, "main_print.gcode"), "w") as f:
        f.writelines(lines)

    entry_file = os.path.join(HOME, "entry_point.txt")
    chunks_dir = os.path.join(HOME, "gcode_chunks")
    if os.path.exists(entry_file):
        os.remove(entry_file)
    shutil.rmtree(chunks_dir, ignore_errors=True)

    result = subprocess.run([program], cwd=HOME, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, \
        f"{program} failed: {result.stderr.decode(errors='replace')}"
    assert os.path.isfile(entry_file), "Program did not create entry_point.txt"
    with open(entry_file, "r") as f:
        text = f.read().strip()
    assert text.lower().startswith("0x"), "Entry point must be written in hexadecimal 0x... format"
    assert int(text, 16) == entry, f"Expected randomized entry point {hex(entry)}, got {text}"

    expected = expected_chunks(lines)
    assert os.path.isdir(chunks_dir), "Program did not create gcode_chunks"
    actual_names = sorted(name for name in os.listdir(chunks_dir)
                          if os.path.isfile(os.path.join(chunks_dir, name)))
    expected_names = [f"chunk_{i:02d}.gcode" for i in range(len(expected))]
    assert actual_names == expected_names, \
        f"Wrong chunk file set: expected {expected_names}, got {actual_names}"
    for name, wanted in zip(expected_names, expected):
        with open(os.path.join(chunks_dir, name), "rb") as f:
            actual = f.read()
        assert actual == wanted, f"Chunk {name} does not exactly match the required input segment"


def test_program_on_derived_inputs():
    """Compile the submitted C source and exercise both it and the required artifact."""
    source = os.path.join(HOME, "organize.c")
    installed = os.path.join(HOME, "organize")
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "organize_rebuilt")
        result = subprocess.run(
            ["/usr/bin/gcc", "-std=c11", "-O2", source, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, \
            f"organize.c does not compile: {result.stderr.decode(errors='replace')}"
        exercise(installed)
        exercise(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
