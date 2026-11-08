#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid


def test_to_delete_log_contents():
    log_path = "/home/user/to_delete.log"
    assert os.path.isfile(log_path), f"Expected log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "/home/user/backups/proj_alpha/test1.gz",
        "/home/user/backups/proj_beta/old/core.gz"
    ]

    assert lines == expected_lines, f"Contents of {log_path} are incorrect. Expected {expected_lines}, got {lines}."


def test_cleanup_tar_exists_and_contents():
    tar_path = "/home/user/cleanup.tar"
    assert os.path.isfile(tar_path), f"Expected tar archive {tar_path} does not exist."

    with tarfile.open(tar_path, "r") as tar:
        members = tar.getmembers()
        filenames = [m.name for m in members]

        assert "to_delete.log" in filenames, "The tar file must contain 'to_delete.log'."
        assert len(filenames) == 1, f"The tar file should only contain one file, but contains: {filenames}"

        f = tar.extractfile("to_delete.log")
        assert f is not None, "Could not extract 'to_delete.log' from tar file."

        content = f.read().decode("utf-8").strip().split("\n")
        lines = [line.strip() for line in content if line.strip()]

        expected_lines = [
            "/home/user/backups/proj_alpha/test1.gz",
            "/home/user/backups/proj_beta/old/core.gz"
        ]

        assert lines == expected_lines, f"Contents of to_delete.log inside the tar file are incorrect. Expected {expected_lines}, got {lines}."


def test_scanner_source_builds_and_scans_dynamic_tree():
    source = "/home/user/scanner.cpp"
    scanner = "/home/user/scanner"
    config = "/home/user/config.txt"
    log_path = "/home/user/to_delete.log"

    assert os.path.isfile(source), f"Expected C++ source file {source} does not exist."
    assert os.path.isfile(scanner), f"Expected compiled scanner {scanner} does not exist."
    assert os.access(scanner, os.X_OK), f"Expected {scanner} to be executable."

    token = uuid.uuid4().hex
    root = tempfile.mkdtemp(prefix=f"scanner_verify_{token}_")
    build_path = f"/tmp/scanner_build_{token}"
    original_config = open(config, "rb").read()
    original_log = open(log_path, "rb").read() if os.path.isfile(log_path) else None

    try:
        nested = os.path.join(root, f"nested_{token[:8]}", f"deep_{token[8:16]}")
        os.makedirs(nested)

        valid_paths = [
            os.path.join(root, f"zeta_{token[16:24]}.gz"),
            os.path.join(nested, f"alpha_{token[24:32]}.gz"),
        ]
        invalid_paths = [
            os.path.join(root, f"elf32_{token[:10]}.gz"),
            os.path.join(nested, f"text_{token[10:20]}.gz"),
        ]

        for path in valid_paths:
            with gzip.open(path, "wb") as f:
                f.write(b"\x7fELF\x02" + os.urandom(27))

        with gzip.open(invalid_paths[0], "wb") as f:
            f.write(b"\x7fELF\x01" + os.urandom(27))
        with gzip.open(invalid_paths[1], "wb") as f:
            f.write(b"ordinary compressed data " + os.urandom(16))

        # A matching payload without the required .gz suffix must not be selected.
        with gzip.open(os.path.join(root, f"ignored_{token}.gzip"), "wb") as f:
            f.write(b"\x7fELF\x02" + os.urandom(12))

        compile_result = subprocess.run(
            ["g++", source, "-o", build_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "scanner.cpp did not build successfully with g++:\n" + compile_result.stderr
        )

        os.replace(build_path, scanner)
        os.chmod(scanner, 0o755)

        with open(config, "w", encoding="utf-8") as f:
            f.write(f"TargetDirectory={root}\n")
        if os.path.lexists(log_path):
            os.remove(log_path)

        run_result = subprocess.run(
            [scanner],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert run_result.returncode == 0, (
            f"Scanner exited with status {run_result.returncode}. stderr:\n{run_result.stderr}"
        )
        assert os.path.isfile(log_path), "Executing the scanner did not create /home/user/to_delete.log."

        with open(log_path, "r", encoding="utf-8") as f:
            actual = [line.strip() for line in f if line.strip()]
        expected = sorted(os.path.abspath(path) for path in valid_paths)
        assert actual == expected, f"Scanner output for the dynamic tree was incorrect. Expected {expected}, got {actual}."
    finally:
        with open(config, "wb") as f:
            f.write(original_config)
        if original_log is None:
            if os.path.lexists(log_path):
                os.remove(log_path)
        else:
            with open(log_path, "wb") as f:
                f.write(original_log)
        if os.path.exists(build_path):
            os.remove(build_path)
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
