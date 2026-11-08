#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/project"
DATA_DIR = os.path.join(PROJECT_DIR, "data")
SECRET_FILE = "/home/user/secret.txt"
SUMMARY_FILE = os.path.join(PROJECT_DIR, "summary.json")
BUILD_SCRIPT = os.path.join(PROJECT_DIR, "build.sh")
PROCESSOR_SCRIPT = os.path.join(PROJECT_DIR, "processor.py")


def read_summary(context=""):
    assert os.path.isfile(SUMMARY_FILE), f"Summary file {SUMMARY_FILE} is missing{context}."
    with open(SUMMARY_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"summary.json is not valid JSON{context}.")
    assert "total_sum" in data, f"summary.json is missing 'total_sum' key{context}."
    return data


def run_build(timeout=15):
    try:
        return subprocess.run(
            ["bash", BUILD_SCRIPT],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("build.sh timed out. Make sure it waits for all background processes without hanging.")


def test_secret_recovered():
    assert os.path.isfile(SECRET_FILE), f"Secret file {SECRET_FILE} is missing."
    with open(SECRET_FILE, "r") as f:
        content = f.read().strip()
    assert content == "S3cr3t_P4ssW0rd_992!", f"Secret file contains incorrect content: {content}"


def test_summary_json_is_correct():
    data = read_summary()
    assert data["total_sum"] == 150, f"Expected total_sum to be 150, but got {data['total_sum']}."


def test_build_script_runs_successfully_and_safely():
    assert os.path.isfile(BUILD_SCRIPT), f"Build script {BUILD_SCRIPT} is missing."
    result = run_build(timeout=10)
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}. stderr: {result.stderr}"
    )
    data = read_summary(" after running build.sh")
    assert data["total_sum"] == 150, (
        f"Expected total_sum to be 150 after running build.sh, but got {data['total_sum']}. "
        "Race condition or file space issue might still exist."
    )


def test_build_handles_unseen_files_values_and_spaces():
    backup_root = tempfile.mkdtemp(prefix="verifier-data-")
    backup_data = os.path.join(backup_root, "data")
    summary_existed = os.path.exists(SUMMARY_FILE)
    summary_backup = None
    if summary_existed:
        with open(SUMMARY_FILE, "rb") as f:
            summary_backup = f.read()

    try:
        shutil.move(DATA_DIR, backup_data)
        os.mkdir(DATA_DIR)

        values = [secrets.randbelow(9000) + 1 for _ in range(24)]
        expected = sum(values)
        for index, value in enumerate(values):
            name = f"generated input {index} {secrets.token_hex(4)}.txt"
            with open(os.path.join(DATA_DIR, name), "w") as f:
                f.write(f"{value}\n")

        result = run_build()
        assert result.returncode == 0, (
            f"build.sh failed on generated files with exit code {result.returncode}. "
            f"stderr: {result.stderr}"
        )
        data = read_summary(" after processing generated files")
        assert data["total_sum"] == expected, (
            f"Generated files sum to {expected}, but build.sh produced {data['total_sum']}."
        )
    finally:
        if os.path.isdir(DATA_DIR):
            shutil.rmtree(DATA_DIR)
        if os.path.exists(backup_data):
            shutil.move(backup_data, DATA_DIR)
        shutil.rmtree(backup_root, ignore_errors=True)
        if summary_existed:
            with open(SUMMARY_FILE, "wb") as f:
                f.write(summary_backup)
        elif os.path.exists(SUMMARY_FILE):
            os.remove(SUMMARY_FILE)


def test_processor_read_modify_write_is_process_safe():
    assert os.path.isfile(PROCESSOR_SCRIPT), f"Processor script {PROCESSOR_SCRIPT} is missing."
    work = tempfile.mkdtemp(prefix="verifier-processor-")
    summary_existed = os.path.exists(SUMMARY_FILE)
    summary_backup = None
    if summary_existed:
        with open(SUMMARY_FILE, "rb") as f:
            summary_backup = f.read()

    processes = []
    try:
        values = [secrets.randbelow(5000) + 1 for _ in range(40)]
        expected = sum(values)
        paths = []
        for index, value in enumerate(values):
            path = os.path.join(work, f"concurrent value {index} {secrets.token_hex(4)}.txt")
            with open(path, "w") as f:
                f.write(f"{value}\n")
            paths.append(path)

        with open(SUMMARY_FILE, "w") as f:
            json.dump({"total_sum": 0}, f)

        for path in paths:
            processes.append(
                subprocess.Popen(
                    ["python3", PROCESSOR_SCRIPT, path],
                    cwd=PROJECT_DIR,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
            )

        failures = []
        for process in processes:
            try:
                stdout, stderr = process.communicate(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                stdout, stderr = process.communicate()
                pytest.fail("processor.py timed out under concurrent execution.")
            if process.returncode != 0:
                failures.append((process.returncode, stdout, stderr))

        assert not failures, f"processor.py failed during concurrent execution: {failures}"
        data = read_summary(" after direct concurrent processor execution")
        assert data["total_sum"] == expected, (
            f"Concurrent processor calls should total {expected}, but produced "
            f"{data['total_sum']}; the read-modify-write operation is not process-safe."
        )
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()
        shutil.rmtree(work, ignore_errors=True)
        if summary_existed:
            with open(SUMMARY_FILE, "wb") as f:
                f.write(summary_backup)
        elif os.path.exists(SUMMARY_FILE):
            os.remove(SUMMARY_FILE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
