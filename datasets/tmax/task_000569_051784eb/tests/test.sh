#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import posixpath
import re
import secrets
import shutil
import subprocess
import tarfile
import tempfile
from decimal import Decimal

SCRIPT_PATH = "/home/user/process_matrices.sh"
ARCHIVE_PATH = "/home/user/archive.tar.gz"
RAW_DIR = "/home/user/data/raw"
PROCESSED_DIR = "/home/user/data/processed"
VENV_DIR = "/home/user/venv"

EXPECTED_SUMMARY = [
    "matrix_2.csv: 25.12",
    "matrix_4.csv: 30.50",
]
EXPECTED_FILES = ["matrix_2.csv", "matrix_4.csv", "summary.log"]
UNEXPECTED_FILES = ["matrix_1.csv", "matrix_3.csv"]


def safely_extract(archive_path, destination):
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        for member in tar.getmembers():
            name = member.name.replace("\\", "/")
            normalized = posixpath.normpath(name)
            assert not name.startswith("/"), f"Archive contains absolute path: {name}"
            assert normalized != ".." and not normalized.startswith("../"), (
                f"Archive contains unsafe path: {name}"
            )
            assert member.isdir() or member.isfile(), (
                f"Archive contains unsupported link or special file: {name}"
            )
        tar.extractall(destination)


def find_processed_dir(extracted_root):
    summary_paths = []
    for root, _dirs, files in os.walk(extracted_root):
        if "summary.log" in files:
            summary_paths.append(os.path.join(root, "summary.log"))
    assert len(summary_paths) == 1, (
        f"Expected exactly one summary.log in archive, found {len(summary_paths)}"
    )
    return os.path.dirname(summary_paths[0])


def read_nonempty_lines(path):
    with open(path, "r", encoding="utf-8") as handle:
        return [line.strip() for line in handle if line.strip()]


def test_00_original_artifacts_and_assertions():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} does not exist."
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive."

    with tempfile.TemporaryDirectory() as temp_dir:
        safely_extract(ARCHIVE_PATH, temp_dir)
        processed_dir = find_processed_dir(temp_dir)
        lines = read_nonempty_lines(os.path.join(processed_dir, "summary.log"))
        assert lines == EXPECTED_SUMMARY, (
            f"summary.log contents incorrect. Expected {EXPECTED_SUMMARY}, got {lines}"
        )

        extracted_files = set(os.listdir(processed_dir))
        for expected_file in EXPECTED_FILES:
            assert expected_file in extracted_files, (
                f"Expected file {expected_file} not found in archive."
            )
        for unexpected_file in UNEXPECTED_FILES:
            assert unexpected_file not in extracted_files, (
                f"Unexpected file {unexpected_file} found in archive."
            )


def test_10_script_implementation_and_dynamic_processing():
    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as handle:
        source = handle.read()

    assert re.search(r"(^|\s)-m\s+venv(?:\s|$)", source), (
        "The Bash script must create a Python virtual environment with Python's venv module."
    )
    assert "activate" in source and "venv" in source, (
        "The Bash script must activate the virtual environment."
    )
    assert re.search(r"\bnumpy\b", source, re.IGNORECASE), (
        "The Bash script must install and use numpy."
    )
    assert re.search(r"(?:import\s+numpy|from\s+numpy\s+import)", source), (
        "The script's Python computation must import numpy."
    )

    token = secrets.token_hex(6)
    matrices = {
        f"alpha_{token}.csv": [
            [Decimal("4.25"), Decimal("100.0")],
            [Decimal("-3.0"), Decimal("15.74")],
        ],
        f"middle_{token}.csv": [
            [Decimal("12.0"), Decimal("2.0"), Decimal("3.0")],
            [Decimal("4.0"), Decimal("5.0"), Decimal("6.0")],
            [Decimal("7.0"), Decimal("8.0"), Decimal("3.0")],
        ],
        f"omega_{token}.csv": [
            [Decimal("3.25"), Decimal("-8.0"), Decimal("1.0")],
            [Decimal("6.0"), Decimal("10.50"), Decimal("2.0")],
            [Decimal("9.0"), Decimal("4.0"), Decimal("9.71")],
        ],
        f"reject_{token}.csv": [
            [Decimal("-10.0"), Decimal("1.0")],
            [Decimal("2.0"), Decimal("29.0")],
        ],
    }

    shutil.rmtree(RAW_DIR, ignore_errors=True)
    shutil.rmtree(PROCESSED_DIR, ignore_errors=True)
    if os.path.lexists(ARCHIVE_PATH):
        os.remove(ARCHIVE_PATH)
    os.makedirs(RAW_DIR, exist_ok=True)

    original_bytes = {}
    expected_lines = []
    expected_copied = set()
    for filename, matrix in matrices.items():
        text = "\n".join(
            ",".join(str(value) for value in row) for row in matrix
        ) + "\n"
        data = text.encode("utf-8")
        original_bytes[filename] = data
        with open(os.path.join(RAW_DIR, filename), "wb") as handle:
            handle.write(data)

        trace = sum((matrix[i][i] for i in range(len(matrix))), Decimal("0"))
        if trace >= Decimal("20.0"):
            expected_copied.add(filename)
            expected_lines.append(f"{filename}: {trace:.2f}")

    expected_lines.sort()
    with open(os.path.join(RAW_DIR, f"ignore_{token}.txt"), "w", encoding="utf-8") as handle:
        handle.write("This is not a CSV and must not be processed.\n")

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}:\n{result.stdout}"
    )

    venv_python = os.path.join(VENV_DIR, "bin", "python")
    assert os.path.isfile(os.path.join(VENV_DIR, "pyvenv.cfg")), (
        f"A real virtual environment was not found at {VENV_DIR}."
    )
    assert os.path.isfile(venv_python) and os.access(venv_python, os.X_OK), (
        "The virtual environment does not contain an executable Python interpreter."
    )
    numpy_check = subprocess.run(
        [venv_python, "-c", "import os,sys,numpy; print(sys.prefix); print(os.path.realpath(numpy.__file__))"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert numpy_check.returncode == 0, (
        f"numpy is not importable from the required virtual environment:\n{numpy_check.stdout}"
    )
    numpy_output = numpy_check.stdout.splitlines()
    assert numpy_output and os.path.realpath(numpy_output[0]) == os.path.realpath(VENV_DIR), (
        "The checked Python interpreter is not using /home/user/venv as its environment."
    )
    assert len(numpy_output) >= 2 and os.path.realpath(numpy_output[1]).startswith(
        os.path.realpath(VENV_DIR) + os.sep
    ), "numpy was not installed inside /home/user/venv."

    assert os.path.isdir(PROCESSED_DIR), "The processed directory was not created."
    live_files = set(os.listdir(PROCESSED_DIR))
    assert live_files == expected_copied | {"summary.log"}, (
        f"Processed directory contents are incorrect: {sorted(live_files)}"
    )
    assert read_nonempty_lines(os.path.join(PROCESSED_DIR, "summary.log")) == expected_lines
    for filename in expected_copied:
        with open(os.path.join(PROCESSED_DIR, filename), "rb") as handle:
            assert handle.read() == original_bytes[filename], (
                f"Processed copy of {filename} does not preserve the input CSV bytes."
            )

    with tempfile.TemporaryDirectory() as temp_dir:
        safely_extract(ARCHIVE_PATH, temp_dir)
        archived_processed = find_processed_dir(temp_dir)
        archived_files = set(os.listdir(archived_processed))
        assert archived_files == expected_copied | {"summary.log"}, (
            f"Archive contents are incorrect: {sorted(archived_files)}"
        )
        archived_lines = read_nonempty_lines(
            os.path.join(archived_processed, "summary.log")
        )
        assert archived_lines == expected_lines, (
            f"Dynamic summary incorrect. Expected {expected_lines}, got {archived_lines}"
        )
        assert archived_lines == sorted(archived_lines), "summary.log is not alphabetically sorted."
        for filename in expected_copied:
            with open(os.path.join(archived_processed, filename), "rb") as handle:
                assert handle.read() == original_bytes[filename], (
                    f"Archived copy of {filename} does not preserve the input CSV bytes."
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
