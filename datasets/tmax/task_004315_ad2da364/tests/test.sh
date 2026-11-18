#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
import uuid


def test_c_program_exists():
    assert os.path.isfile("/home/user/doc_extractor.c"), "C source code /home/user/doc_extractor.c is missing."
    assert os.path.isfile("/home/user/doc_extractor"), "Compiled executable /home/user/doc_extractor is missing."
    assert os.access("/home/user/doc_extractor", os.X_OK), "Compiled executable is not marked as executable."
    with open("/home/user/doc_extractor", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/doc_extractor is not a compiled ELF executable."


def test_extracted_files_content():
    expected_files = {
        "readme.txt": b"Welcome to the robotics documentation.\n" * 5,
        "calibrate.gcode": b"G28 X Y Z\nG1 X100 Y100 F3000\n" * 3,
        "firmware_boot.elf": b"\x7FELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" + b"\x00" * 50
    }

    for filename, expected_data in expected_files.items():
        path = f"/home/user/extracted/{filename}"
        assert os.path.isfile(path), f"Extracted file is missing: {path}"
        with open(path, "rb") as f:
            data = f.read()
        assert data == expected_data, f"Content mismatch for {path}"


def test_symlinks_exist_and_correct():
    expected_symlinks = {
        "/home/user/docs/by_type/text/readme.txt": "/home/user/extracted/readme.txt",
        "/home/user/docs/by_type/gcode/calibrate.gcode": "/home/user/extracted/calibrate.gcode",
        "/home/user/docs/by_type/elf/firmware_boot.elf": "/home/user/extracted/firmware_boot.elf"
    }

    for symlink_path, target_path in expected_symlinks.items():
        assert os.path.islink(symlink_path), f"Expected symbolic link missing or not a symlink: {symlink_path}"
        actual_target = os.readlink(symlink_path)
        if not os.path.isabs(actual_target):
            actual_target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), actual_target))
        assert actual_target == target_path, f"Symlink {symlink_path} points to {actual_target}, expected {target_path}"


def test_manifest_content():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file missing: {manifest_path}"

    expected_lines = [
        "/home/user/docs/by_type/elf/firmware_boot.elf",
        "/home/user/docs/by_type/gcode/calibrate.gcode",
        "/home/user/docs/by_type/text/readme.txt"
    ]

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_lines, "Manifest contents do not match expected sorted list of absolute paths."


def rle_compress(data):
    result = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i + count] == data[i] and count < 255:
            count += 1
        result.extend((count, data[i]))
        i += count
    return bytes(result)


def make_archive():
    token = uuid.uuid4().hex[:12]
    files = {
        f"{token}.txt": secrets.token_bytes(37) + b"A" * 300 + b"\x00\xff\n",
        f"{token}.gcode": b"G1 X" + secrets.token_bytes(23) + b"Z" * 19,
        f"{token}.elf": b"\x7fELF" + secrets.token_bytes(61) + b"\x00" * 270,
    }
    archive = bytearray(b"DOCP")
    archive.extend(struct.pack("<I", len(files)))
    for type_id, (name, data) in enumerate(files.items()):
        encoded_name = name.encode("ascii")
        assert len(encoded_name) < 32
        compressed = rle_compress(data)
        archive.extend(encoded_name + b"\x00" * (32 - len(encoded_name)))
        archive.append(type_id)
        archive.extend(struct.pack("<I", len(compressed)))
        archive.extend(compressed)
    return bytes(archive), files


def exercise_extractor(executable):
    archive, expected = make_archive()
    output_dir = "/home/user/extracted"
    os.makedirs(output_dir, exist_ok=True)
    paths = [os.path.join(output_dir, name) for name in expected]
    try:
        result = subprocess.run(
            [executable],
            input=archive,
            cwd=output_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, (
            f"Extractor exited with status {result.returncode}: "
            + result.stderr.decode("utf-8", "replace")
        )
        for name, wanted in expected.items():
            path = os.path.join(output_dir, name)
            assert os.path.isfile(path), f"Extractor did not create stdin-supplied file {path}"
            with open(path, "rb") as f:
                actual = f.read()
            assert actual == wanted, f"Extractor incorrectly parsed or decompressed {name}"
    finally:
        for path in paths:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_executable_parses_dynamic_archive_from_stdin():
    exercise_extractor("/home/user/doc_extractor")


def test_source_builds_and_implements_extractor():
    with tempfile.TemporaryDirectory() as build_dir:
        rebuilt = os.path.join(build_dir, "doc_extractor")
        result = subprocess.run(
            ["gcc", "-std=c11", "-O2", "/home/user/doc_extractor.c", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert result.returncode == 0, "C source does not compile: " + result.stderr.decode("utf-8", "replace")
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF"
        exercise_extractor(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
