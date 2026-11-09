#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile
import pytest


def original_files():
    print_a = (
        "; Start GCode\n"
        "M104 S200 ; Set nozzle temp\n"
        "M140 S60 ; Set bed temp\n"
        "G28 ; Home all axes\n"
        "G1 Z5.0 F3000 ; Move Z up\n"
        + "".join(
            f"G1 X{i} Y{i} E0.1 ; inline comment {i}\n"
            for i in range(1, 107)
        )
    )
    print_b = (
        "; Another file\n"
        "; with a lot of\n"
        "; comment lines\n"
        "\n"
        + "".join(f"G0 Z{i}\n" for i in range(1, 41))
    )
    return {
        "printA.gcode": print_a.encode("utf-8"),
        "printB.gcode": print_b.encode("utf-8"),
    }


def clean_commands(raw):
    commands = []
    for line in raw.decode("utf-8").splitlines():
        command = line.split(";", 1)[0].strip()
        if command:
            commands.append(command)
    return commands


def test_backup_exists_and_valid():
    """Test that the backup contains the exact original, unmodified files."""
    backup_path = "/home/user/backup/raw_archive.tar.gz"
    assert os.path.isfile(backup_path), f"Backup archive {backup_path} is missing."

    expected = original_files()
    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            names = tar.getnames()
            assert any(name.endswith("printA.gcode") for name in names), "printA.gcode not found in backup archive."
            assert any(name.endswith("printB.gcode") for name in names), "printB.gcode not found in backup archive."

            members = tar.getmembers()
            regular = [member for member in members if member.isfile()]
            assert all(member.isfile() or member.isdir() for member in members), "Archive contains non-file entries."

            normalized_files = {member.name.lstrip("./").rstrip("/") for member in regular}
            allowed_layouts = [
                {"printA.gcode", "printB.gcode"},
                {"raw_gcode/printA.gcode", "raw_gcode/printB.gcode"},
            ]
            assert normalized_files in allowed_layouts, f"Unexpected archive layout or files: {normalized_files}"
            assert len(regular) == 2, "Archive must contain exactly the two original GCode files."

            for member in regular:
                normalized = member.name.lstrip("./").rstrip("/")
                basename = normalized.rsplit("/", 1)[-1]
                extracted = tar.extractfile(member)
                assert extracted is not None
                assert extracted.read() == expected[basename], f"Archived {basename} is not the original unmodified file."

            for member in members:
                if member.isdir():
                    normalized = member.name.lstrip("./").rstrip("/")
                    assert normalized in ("", "raw_gcode"), f"Unexpected directory in archive: {member.name}"
    except tarfile.ReadError:
        pytest.fail(f"Backup archive {backup_path} is not a valid tar.gz file.")


def test_source_dir_empty():
    """Test that the source directory contains no .gcode files after processing."""
    source_dir = "/home/user/raw_gcode"
    assert os.path.isdir(source_dir), f"Source directory {source_dir} is missing."

    files = os.listdir(source_dir)
    gcode_files = [f for f in files if f.endswith(".gcode")]
    assert len(gcode_files) == 0, f"Source directory {source_dir} still contains .gcode files: {gcode_files}"


def test_processed_gcode_chunks():
    """Test chunk names, sizes, formatting, and exact transformed command contents."""
    dest_dir = "/home/user/processed_gcode"
    assert os.path.isdir(dest_dir), f"Destination directory {dest_dir} is missing."

    expected_files = {
        "printA_part1.gcode": 50,
        "printA_part2.gcode": 50,
        "printA_part3.gcode": 10,
        "printB_part1.gcode": 40,
    }

    expected_contents = {}
    for source_name, raw in original_files().items():
        stem = os.path.splitext(source_name)[0]
        commands = clean_commands(raw)
        for index, start in enumerate(range(0, len(commands), 50), 1):
            chunk = commands[start:start + 50]
            expected_contents[f"{stem}_part{index}.gcode"] = "".join(
                command + "\n" for command in chunk
            ).encode("utf-8")

    assert set(expected_contents) == set(expected_files)
    actual_files = [f for f in os.listdir(dest_dir) if f.endswith(".gcode")]

    for expected_file, expected_lines in expected_files.items():
        assert expected_file in actual_files, f"Expected chunk {expected_file} is missing."

        filepath = os.path.join(dest_dir, expected_file)
        assert os.path.isfile(filepath), f"Chunk {expected_file} is not a regular file."
        with open(filepath, "r") as f:
            lines = f.readlines()

        assert len(lines) == expected_lines, f"File {expected_file} has {len(lines)} lines, expected {expected_lines}."

        for line in lines:
            assert ";" not in line, f"Found comment in {expected_file}: {line.strip()}"
            assert line.strip() != "", f"Found empty line in {expected_file}"
            assert line == line.strip() + "\n", f"Line not stripped properly in {expected_file}: '{line}'"

        with open(filepath, "rb") as f:
            actual_content = f.read()
        assert actual_content == expected_contents[expected_file], f"Chunk {expected_file} does not contain the expected transformed commands."

    unexpected_files = set(actual_files) - set(expected_files.keys())
    assert not unexpected_files, f"Found unexpected .gcode files in destination directory: {unexpected_files}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
