#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path


def test_extracted_files_renamed():
    extracted_dir = "/home/user/extracted"
    assert os.path.isdir(extracted_dir), f"Directory {extracted_dir} does not exist"

    expected_files = {
        "patient_x_read1.fq",
        "patient_x_read2.fq",
        "patient_y_read1.fq",
        "patient_y_read2.fq",
        "unmapped_data.txt"
    }

    actual_files = set(os.listdir(extracted_dir))

    missing_files = expected_files - actual_files
    unexpected_files = actual_files - expected_files

    assert not missing_files, f"Missing expected files in {extracted_dir}: {missing_files}"
    assert not unexpected_files, f"Unexpected files found in {extracted_dir} (did not rename correctly or extracted extra files): {unexpected_files}"


def test_rename_log_contents():
    log_file = "/home/user/rename_log.txt"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist"

    expected_lines = {
        "RENAMED: sample1_read1.fq -> patient_x_read1.fq",
        "RENAMED: sample1_read2.fq -> patient_x_read2.fq",
        "RENAMED: sample2_read1.fq -> patient_y_read1.fq",
        "RENAMED: sample2_read2.fq -> patient_y_read2.fq"
    }

    with open(log_file, "r") as f:
        actual_lines = {line.strip() for line in f if line.strip()}

    missing_lines = expected_lines - actual_lines
    unexpected_lines = actual_lines - expected_lines

    assert not missing_lines, f"Missing expected log lines: {missing_lines}"
    assert not unexpected_lines, f"Unexpected log lines found: {unexpected_lines}"


def test_python_script_exists():
    script_file = "/home/user/rename.py"
    assert os.path.isfile(script_file), f"Python script {script_file} does not exist"


def _remove_path(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def test_python_script_interprets_mapping_and_renames_dynamic_fixture():
    script_file = "/home/user/rename.py"
    extracted_dir = "/home/user/extracted"
    mapping_file = "/home/user/mapping.ini"
    log_file = "/home/user/rename_log.txt"

    token = secrets.token_hex(12)
    temp_a = f"tmpa_{token}"
    temp_b = f"tmpb_{token}"
    patient_a = f"patienta_{secrets.token_hex(12)}"
    patient_b = f"patientb_{secrets.token_hex(12)}"

    source_files = {
        f"{temp_a}_read1.fq",
        f"{temp_a}_read2.fq",
        f"{temp_b}_lane7.fastq.gz",
        "leave_unmapped.txt",
    }
    expected_files = {
        f"{patient_a}_read1.fq",
        f"{patient_a}_read2.fq",
        f"{patient_b}_lane7.fastq.gz",
        "leave_unmapped.txt",
    }
    expected_output = {
        f"RENAMED: {temp_a}_read1.fq -> {patient_a}_read1.fq",
        f"RENAMED: {temp_a}_read2.fq -> {patient_a}_read2.fq",
        f"RENAMED: {temp_b}_lane7.fastq.gz -> {patient_b}_lane7.fastq.gz",
    }

    backup_root = tempfile.mkdtemp(prefix="rename-verifier-")
    backup_extracted = os.path.join(backup_root, "extracted")
    backup_mapping = os.path.join(backup_root, "mapping.ini")
    backup_log = os.path.join(backup_root, "rename_log.txt")

    os.replace(extracted_dir, backup_extracted)
    os.replace(mapping_file, backup_mapping)
    log_existed = os.path.exists(log_file)
    if log_existed:
        os.replace(log_file, backup_log)

    try:
        os.mkdir(extracted_dir)
        for filename in source_files:
            Path(extracted_dir, filename).write_bytes(b"dynamic test data\n")

        Path(mapping_file).write_text(
            f"[Renames]\n{temp_a} = {patient_a}\n{temp_b} = {patient_b}\n",
            encoding="utf-8",
        )

        result = subprocess.run(
            ["python3", script_file],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )

        assert result.returncode == 0, (
            f"rename.py exited with status {result.returncode}; stderr: {result.stderr}"
        )
        actual_files = set(os.listdir(extracted_dir))
        assert actual_files == expected_files, (
            f"rename.py produced incorrect files: expected {expected_files}, got {actual_files}"
        )
        actual_output = {line.strip() for line in result.stdout.splitlines() if line.strip()}
        assert actual_output == expected_output, (
            f"rename.py produced incorrect stdout: expected {expected_output}, got {actual_output}"
        )
    finally:
        _remove_path(extracted_dir)
        _remove_path(mapping_file)
        _remove_path(log_file)
        os.replace(backup_extracted, extracted_dir)
        os.replace(backup_mapping, mapping_file)
        if log_existed:
            os.replace(backup_log, log_file)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
