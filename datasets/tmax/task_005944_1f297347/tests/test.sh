#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import shutil
import hashlib
import secrets
import subprocess
import sys
import tempfile
import pytest

def get_sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def test_chunk_files_created():
    output_dir = "/home/user/archive_output"

    expected_files = {
        "experiments_run1_sensor_data.dat_part0.chunk": (1024, b"B" * 1024),
        "experiments_run1_sensor_data.dat_part1.chunk": (476, b"B" * 476),
        "main_data.dat_part0.chunk": (1024, b"A" * 1024),
        "main_data.dat_part1.chunk": (1024, b"A" * 1024),
        "main_data.dat_part2.chunk": (452, b"A" * 452),
    }

    for filename, (expected_size, expected_content) in expected_files.items():
        filepath = os.path.join(output_dir, filename)
        assert os.path.isfile(filepath), f"Expected chunk file is missing: {filepath}"

        with open(filepath, "rb") as f:
            content = f.read()

        assert len(content) == expected_size, f"Incorrect file size for {filename}. Expected {expected_size}, got {len(content)}."
        assert content == expected_content, f"Incorrect file content for {filename}."

def test_manifest_file():
    manifest_path = "/home/user/archive_output/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file is missing: {manifest_path}"

    expected_lines = [
        f"{get_sha256(b'B'*1024)}  experiments_run1_sensor_data.dat_part0.chunk",
        f"{get_sha256(b'B'*476)}  experiments_run1_sensor_data.dat_part1.chunk",
        f"{get_sha256(b'A'*1024)}  main_data.dat_part0.chunk",
        f"{get_sha256(b'A'*1024)}  main_data.dat_part1.chunk",
        f"{get_sha256(b'A'*452)}  main_data.dat_part2.chunk"
    ]

    with open(manifest_path, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Manifest has incorrect number of lines. Expected {len(expected_lines)}, got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Manifest line {i+1} is incorrect.\nExpected: '{expected}'\nGot:      '{actual}'"

def test_no_extra_chunks():
    output_dir = "/home/user/archive_output"
    allowed_files = {
        "experiments_run1_sensor_data.dat_part0.chunk",
        "experiments_run1_sensor_data.dat_part1.chunk",
        "main_data.dat_part0.chunk",
        "main_data.dat_part1.chunk",
        "main_data.dat_part2.chunk",
        "manifest.txt"
    }

    actual_files = set(os.listdir(output_dir))
    extra_files = actual_files - allowed_files

    assert not extra_files, f"Found unexpected files in output directory: {extra_files}. Cycle detection may have failed or ignored files were processed."

def test_script_executes_on_unpredictable_config_and_symlink_cycle():
    script_path = "/home/user/archive_data.py"
    assert os.path.exists(script_path), f"Required script is missing: {script_path}"
    mode = os.lstat(script_path).st_mode
    assert stat.S_ISREG(mode), f"Required script is not a regular file: {script_path}"
    assert not os.path.islink(script_path), f"Required script must not be a symlink: {script_path}"

    dataset = "/home/user/dataset"
    token = secrets.token_hex(8)
    backup = f"/tmp/dataset-backup-{token}"
    sandbox = tempfile.mkdtemp(prefix="archive-verifier-")
    external = os.path.join(sandbox, "external", "deep")
    output_dir = os.path.join(sandbox, "generated-output")
    extension = f".q{token}"
    chunk_size = 173 + secrets.randbelow(259)
    direct_data = secrets.token_bytes(chunk_size * 2 + 19)
    linked_data = secrets.token_bytes(chunk_size + 7)
    ignored_data = secrets.token_bytes(chunk_size + 31)

    os.rename(dataset, backup)
    try:
        os.makedirs(dataset)
        os.makedirs(external)

        with open(os.path.join(dataset, "config.ini"), "w", encoding="utf-8") as f:
            f.write("[Archive]\n")
            f.write(f"chunk_size_bytes = {chunk_size}\n")
            f.write(f"target_extension = {extension}\n")
            f.write(f"output_dir = {output_dir}\n")

        with open(os.path.join(dataset, f"top{extension}"), "wb") as f:
            f.write(direct_data)
        with open(os.path.join(dataset, "ignored.dat"), "wb") as f:
            f.write(ignored_data)
        with open(os.path.join(external, f"linked{extension}"), "wb") as f:
            f.write(linked_data)

        # The matching linked file is only reachable by following this directory
        # symlink. The back-link creates a real traversal cycle.
        os.symlink(external, os.path.join(dataset, "via_link"))
        os.symlink(dataset, os.path.join(external, "back_to_dataset"))

        try:
            result = subprocess.run(
                [sys.executable, script_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired as exc:
            pytest.fail(f"archive_data.py did not terminate while traversing a symlink cycle: {exc}")

        assert result.returncode == 0, (
            f"archive_data.py failed on a valid generated configuration.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        expected_chunks = {}
        for relative_name, data in (
            (f"top{extension}", direct_data),
            (f"via_link_linked{extension}", linked_data),
        ):
            for part, start in enumerate(range(0, len(data), chunk_size)):
                filename = f"{relative_name}_part{part}.chunk"
                expected_chunks[filename] = data[start:start + chunk_size]

        assert os.path.isdir(output_dir), "Configured output directory was not created"
        expected_names = set(expected_chunks) | {"manifest.txt"}
        actual_names = set(os.listdir(output_dir))
        assert actual_names == expected_names, (
            f"Generated output files are incorrect. Expected {sorted(expected_names)}, "
            f"got {sorted(actual_names)}"
        )

        for filename, expected_content in expected_chunks.items():
            path = os.path.join(output_dir, filename)
            assert os.path.isfile(path), f"Missing generated chunk: {filename}"
            with open(path, "rb") as f:
                actual_content = f.read()
            assert actual_content == expected_content, f"Incorrect generated content for {filename}"
            assert 0 < len(actual_content) <= chunk_size

        expected_manifest = [
            f"{hashlib.sha256(expected_chunks[name]).hexdigest()}  {name}"
            for name in sorted(expected_chunks)
        ]
        manifest_path = os.path.join(output_dir, "manifest.txt")
        assert os.path.isfile(manifest_path), "Generated manifest is missing"
        with open(manifest_path, "r", encoding="utf-8") as f:
            actual_manifest = f.read().splitlines()
        assert actual_manifest == expected_manifest, (
            f"Generated manifest is incorrect.\nExpected: {expected_manifest}\n"
            f"Got: {actual_manifest}"
        )
    finally:
        if os.path.lexists(dataset):
            if os.path.isdir(dataset) and not os.path.islink(dataset):
                shutil.rmtree(dataset)
            else:
                os.unlink(dataset)
        if os.path.exists(backup):
            os.rename(backup, dataset)
        shutil.rmtree(sandbox, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
