#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import shutil
import subprocess
import tempfile
import secrets


def test_cpp_file_exists():
    cpp_file = "/home/user/split_assets.cpp"
    assert os.path.isfile(cpp_file), f"Expected C++ source file {cpp_file} does not exist."


def test_output_files_exist_and_sizes():
    expected_files = {
        "level1.bin": 2048,
        "level2.bin": 4096,
        "sprites.bin": 1024,
        "audio.bin": 2048,
        "remainder.bin": 1024
    }

    for filename, expected_size in expected_files.items():
        filepath = f"/home/user/output/{filename}"
        assert os.path.isfile(filepath), f"Expected output file {filepath} does not exist."
        actual_size = os.path.getsize(filepath)
        assert actual_size == expected_size, f"File {filepath} should be {expected_size} bytes, but is {actual_size} bytes."


def test_concatenated_content_matches_original():
    files_in_order = [
        "/home/user/output/level1.bin",
        "/home/user/output/level2.bin",
        "/home/user/output/sprites.bin",
        "/home/user/output/audio.bin",
        "/home/user/output/remainder.bin"
    ]

    concatenated_data = bytearray()
    for filepath in files_in_order:
        assert os.path.isfile(filepath), f"Missing file for concatenation: {filepath}"
        with open(filepath, "rb") as f:
            concatenated_data.extend(f.read())

    original_data_file = "/home/user/project_data.bin"
    assert os.path.isfile(original_data_file), f"Original data file {original_data_file} is missing."

    with open(original_data_file, "rb") as f:
        original_data = f.read()

    assert concatenated_data == original_data, "The concatenated output files do not match the original project_data.bin."


def test_manifest_sha256():
    manifest_file = "/home/user/output/manifest.sha256"
    assert os.path.isfile(manifest_file), f"Manifest file {manifest_file} does not exist."

    expected_files = [
        "level1.bin",
        "level2.bin",
        "sprites.bin",
        "audio.bin",
        "remainder.bin"
    ]

    result = subprocess.run(
        ["sha256sum", "-c", "manifest.sha256"],
        cwd="/home/user/output",
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"sha256sum validation failed. Output:\n{result.stdout}\n{result.stderr}"

    with open(manifest_file, "r") as f:
        manifest_content = f.read()

    for filename in expected_files:
        assert filename in manifest_content, f"File {filename} is missing from the manifest."


def test_cpp_program_compiles_and_performs_split():
    source = "/home/user/split_assets.cpp"
    config = "/home/user/split_config.txt"
    data_file = "/home/user/project_data.bin"
    output_dir = "/home/user/output"

    with tempfile.TemporaryDirectory() as temp_dir:
        executable = os.path.join(temp_dir, "split_assets")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", source, "-o", executable],
            capture_output=True,
            text=True
        )
        assert compile_result.returncode == 0, (
            "split_assets.cpp failed to compile:\n"
            + compile_result.stdout + compile_result.stderr
        )

        saved_config = os.path.join(temp_dir, "split_config.txt")
        saved_data = os.path.join(temp_dir, "project_data.bin")
        saved_output = os.path.join(temp_dir, "saved_output")
        shutil.copy2(config, saved_config)
        shutil.copy2(data_file, saved_data)
        shutil.copytree(output_dir, saved_output)

        token = secrets.token_hex(8)
        entries = [
            (f"probe_{token}_one.bin", 137),
            (f"probe_{token}_two.bin", 911),
            (f"probe_{token}_three.bin", 53),
        ]
        remainder_size = 317
        probe_data = os.urandom(sum(size for _, size in entries) + remainder_size)

        try:
            with open(config, "w", encoding="utf-8") as f:
                for filename, size in entries:
                    f.write(f"{filename} {size}\n")
            with open(data_file, "wb") as f:
                f.write(probe_data)

            shutil.rmtree(output_dir)
            os.mkdir(output_dir)

            run_result = subprocess.run(
                [executable],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=15
            )
            assert run_result.returncode == 0, (
                "Compiled split_assets program failed when run:\n"
                + run_result.stdout + run_result.stderr
            )

            offset = 0
            for filename, size in entries:
                filepath = os.path.join(output_dir, filename)
                assert os.path.isfile(filepath), f"Program did not create {filepath}"
                with open(filepath, "rb") as f:
                    actual = f.read()
                expected = probe_data[offset:offset + size]
                assert actual == expected, f"Program wrote incorrect content to {filename}"
                offset += size

            remainder_path = os.path.join(output_dir, "remainder.bin")
            assert os.path.isfile(remainder_path), "Program did not create remainder.bin"
            with open(remainder_path, "rb") as f:
                actual_remainder = f.read()
            assert actual_remainder == probe_data[offset:], "Program wrote incorrect remainder data"
        finally:
            shutil.copy2(saved_config, config)
            shutil.copy2(saved_data, data_file)
            if os.path.exists(output_dir):
                shutil.rmtree(output_dir)
            shutil.copytree(saved_output, output_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
