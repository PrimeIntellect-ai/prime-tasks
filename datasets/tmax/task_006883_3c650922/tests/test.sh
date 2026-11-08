#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import uuid
from pathlib import Path

import pytest


def test_00_compiled_rust_application_and_unseen_inputs():
    project_dir = Path("/home/user/gcode_archiver")
    executable = project_dir / "target/debug/gcode_archiver"

    assert project_dir.is_dir(), f"Expected Rust project directory {project_dir}."
    assert any(path.is_file() for path in project_dir.rglob("*.rs")), "No Rust source file was found."
    assert executable.is_file(), f"Expected compiled executable {executable}."
    assert os.access(executable, os.X_OK), f"Expected {executable} to be executable."
    with executable.open("rb") as binary:
        assert binary.read(4) == b"\x7fELF", f"Expected {executable} to be a compiled ELF binary."

    source_dir = Path("/home/user/gcode_files")
    long_dir = Path("/home/user/archive/long_prints")
    short_dir = Path("/home/user/archive/short_prints")
    token = uuid.uuid4().hex
    rng = random.SystemRandom()

    cases = [
        (f"audit_{token}_boundary.gcode", 7200),
        (f"audit_{token}_long.gcode", rng.randint(7201, 20000)),
        (f"audit_{token}_short.gcode", rng.randint(1, 7199)),
        (f"audit_{token}_missing.gcode", None),
    ]

    input_paths = []
    for filename, seconds in cases:
        source = source_dir / filename
        if seconds is None:
            source.write_text("G28\n; metadata intentionally absent\nM104 S0\n")
        else:
            source.write_text(
                f"G28\nG1 X1 Y1\n; estimated_time_s: {seconds}\nM104 S0\n"
            )
        input_paths.append(str(source))

        for destination in (long_dir / filename, short_dir / filename):
            if os.path.lexists(destination):
                destination.unlink()

    result = subprocess.run(
        [str(executable)],
        input="\n".join(input_paths) + "\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Application exited with {result.returncode}. stderr: {result.stderr}"
    )

    for filename, seconds in cases:
        source = source_dir / filename
        long_path = long_dir / filename
        short_path = short_dir / filename

        if seconds is None:
            assert not os.path.lexists(long_path), f"Metadata-free file appeared in {long_dir}."
            assert not os.path.lexists(short_path), f"Metadata-free file appeared in {short_dir}."
        elif seconds >= 7200:
            assert long_path.exists(), f"Expected hard link {long_path} does not exist."
            assert not long_path.is_symlink(), f"Expected {long_path} to be a hard link."
            source_stat = source.stat()
            archived_stat = long_path.stat()
            assert source_stat.st_ino == archived_stat.st_ino
            assert source_stat.st_dev == archived_stat.st_dev
            assert not os.path.lexists(short_path), f"Long print incorrectly appeared in {short_dir}."
        else:
            assert short_path.is_symlink(), f"Expected {short_path} to be a symlink."
            assert os.readlink(short_path) == str(source)
            assert not os.path.lexists(long_path), f"Short print incorrectly appeared in {long_dir}."


def test_hard_links_for_long_prints():
    long_prints = [
        ("part_A.gcode", "/home/user/gcode_files/part_A.gcode"),
        ("part_D.gcode", "/home/user/gcode_files/part_D.gcode"),
    ]

    long_prints_dir = "/home/user/archive/long_prints"

    for filename, original_path in long_prints:
        archived_path = os.path.join(long_prints_dir, filename)

        assert os.path.exists(archived_path), f"Expected hard link {archived_path} does not exist."
        assert not os.path.islink(archived_path), f"Expected {archived_path} to be a hard link, but it is a symlink."

        stat_original = os.stat(original_path)
        stat_archived = os.stat(archived_path)

        assert stat_original.st_ino == stat_archived.st_ino, f"File {archived_path} is not a hard link to {original_path} (inodes differ)."
        assert stat_original.st_dev == stat_archived.st_dev, f"File {archived_path} is not on the same device as {original_path}."


def test_symlinks_for_short_prints():
    short_prints = [
        ("part_B.gcode", "/home/user/gcode_files/part_B.gcode"),
    ]

    short_prints_dir = "/home/user/archive/short_prints"

    for filename, original_path in short_prints:
        archived_path = os.path.join(short_prints_dir, filename)

        assert os.path.islink(archived_path), f"Expected {archived_path} to be a symlink."

        target = os.readlink(archived_path)
        assert target == original_path, f"Symlink {archived_path} points to {target}, expected {original_path}."


def test_ignored_files():
    ignored_files = ["part_C.gcode"]
    long_prints_dir = "/home/user/archive/long_prints"
    short_prints_dir = "/home/user/archive/short_prints"

    for filename in ignored_files:
        long_path = os.path.join(long_prints_dir, filename)
        short_path = os.path.join(short_prints_dir, filename)

        assert not os.path.exists(long_path) and not os.path.islink(long_path), f"File {filename} should be ignored, but found in {long_prints_dir}."
        assert not os.path.exists(short_path) and not os.path.islink(short_path), f"File {filename} should be ignored, but found in {short_prints_dir}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
