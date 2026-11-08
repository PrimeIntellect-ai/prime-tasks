#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pytest

DATASET_DIR = "/home/user/dataset"
SUMMARY_LOG = "/home/user/summary.log"

EXPECTED_FILES = [
    "A1B2C3D4.dat",
    "F9E8D7C6.dat",
    "MNBVCXZA.dat",
    "Q1W2E3R4.dat",
    "ZZ99YY88.dat"
]

SIGNATURE_LINE_INDEX = 4989


def test_no_raw_data_files():
    """Ensure original raw_data_*.dat files no longer exist."""
    assert os.path.isdir(DATASET_DIR), f"Directory {DATASET_DIR} does not exist."
    files = os.listdir(DATASET_DIR)
    raw_files = [f for f in files if f.startswith("raw_data_") and f.endswith(".dat")]
    assert len(raw_files) == 0, f"Original raw_data files still exist: {raw_files}"


def test_renamed_files_exist():
    """Ensure the files are renamed to their experiment IDs."""
    assert os.path.isdir(DATASET_DIR), f"Directory {DATASET_DIR} does not exist."
    files = os.listdir(DATASET_DIR)
    dat_files = [f for f in files if f.endswith(".dat")]

    assert set(dat_files) == set(EXPECTED_FILES), (
        f"Expected .dat files {EXPECTED_FILES}, but found {dat_files}"
    )


@pytest.mark.parametrize("filename", EXPECTED_FILES)
def test_cleaned_headers(filename):
    """Ensure the first 10 lines were removed and exactly 9,990 lines remain."""
    filepath = os.path.join(DATASET_DIR, filename)
    assert os.path.isfile(filepath), f"Expected file {filepath} is missing."

    with open(filepath, 'r') as f:
        lines = f.readlines()

    assert len(lines) == 9990, f"File {filename} should have exactly 9,990 lines, but has {len(lines)}."
    assert lines[0].startswith("1234567890, "), f"First line of {filename} does not look like data. Headers might not be fully removed."
    assert "JUNK HEADER LINE" not in lines[0], f"First line of {filename} still contains header junk."


def test_preserved_sensor_data_and_embedded_ids():
    """Check every record, the original signature position, and non-repeated sensor values."""
    all_values = set()
    total_values = 0

    for filename in EXPECTED_FILES:
        experiment_id = filename[:-4]
        filepath = os.path.join(DATASET_DIR, filename)
        with open(filepath, "rb") as f:
            raw_lines = f.readlines()

        assert len(raw_lines) == 9990
        assert all(line.endswith(b"\n") for line in raw_lines), f"Malformed line ending in {filename}"

        expected_signature = (
            b"1234567890, 0.00 MAGIC_SIG:"
            + experiment_id.encode("ascii")
            + b" END\n"
        )
        signature_lines = [i for i, line in enumerate(raw_lines) if b"MAGIC_SIG:" in line]
        assert signature_lines == [SIGNATURE_LINE_INDEX], (
            f"{filename} must contain its single embedded ID at the original data position"
        )
        assert raw_lines[SIGNATURE_LINE_INDEX] == expected_signature, (
            f"Embedded experiment ID in {filename} does not match its filename"
        )

        for i, line in enumerate(raw_lines):
            if i == SIGNATURE_LINE_INDEX:
                continue
            try:
                text = line.decode("ascii")
            except UnicodeDecodeError as exc:
                pytest.fail(f"Non-ASCII sensor record in {filename}: {exc}")
            assert text.startswith("1234567890, ") and text.endswith("\n"), (
                f"Malformed sensor record at line {i + 1} of {filename}"
            )
            value_text = text[len("1234567890, "):-1]
            assert value_text and not value_text.strip() != value_text, (
                f"Malformed numeric value at line {i + 1} of {filename}"
            )
            try:
                value = float(value_text)
            except ValueError:
                pytest.fail(f"Invalid sensor value at line {i + 1} of {filename}")
            assert 0.0 <= value < 1.0, f"Out-of-range sensor value in {filename}"
            assert str(value) == value_text, f"Sensor value formatting was changed in {filename}"
            assert value_text not in all_values, (
                "Sensor records contain repeated/generated filler instead of the preserved data"
            )
            all_values.add(value_text)
            total_values += 1

    assert total_values == 49945


def _uses_mmap_for_magic_search(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            source = f.read(1024 * 1024 + 1)
        if len(source) > 1024 * 1024:
            return False
        tree = ast.parse(source, filename=path)
    except (OSError, UnicodeError, SyntaxError):
        return False

    mmap_modules = set()
    mmap_functions = set()
    has_marker = False

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "mmap":
                    mmap_modules.add(alias.asname or "mmap")
        elif isinstance(node, ast.ImportFrom) and node.module == "mmap":
            for alias in node.names:
                if alias.name == "mmap":
                    mmap_functions.add(alias.asname or "mmap")
        elif isinstance(node, ast.Constant) and isinstance(node.value, (str, bytes)):
            marker = "MAGIC_SIG:" if isinstance(node.value, str) else b"MAGIC_SIG:"
            if marker in node.value:
                has_marker = True

    has_mmap_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id in mmap_functions:
            has_mmap_call = True
        elif (
            isinstance(func, ast.Attribute)
            and func.attr == "mmap"
            and isinstance(func.value, ast.Name)
            and func.value.id in mmap_modules
        ):
            has_mmap_call = True

    return has_marker and has_mmap_call


def test_python_mmap_extraction_script_exists():
    """Require a retained Python implementation that actually calls mmap.mmap."""
    candidates = []
    this_test = os.path.realpath(__file__)
    for root in ("/home/user", "/tmp"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__", ".local"}]
            for name in files:
                if name.endswith(".py"):
                    path = os.path.join(directory, name)
                    if os.path.realpath(path) != this_test:
                        candidates.append(path)

    matching = [path for path in candidates if _uses_mmap_for_magic_search(path)]
    assert matching, (
        "No Python extraction script was found that imports mmap, calls mmap.mmap, "
        "and searches for the MAGIC_SIG: marker"
    )


def test_summary_log():
    """Ensure summary.log contains the sorted list of new filenames."""
    assert os.path.isfile(SUMMARY_LOG), f"Summary log {SUMMARY_LOG} does not exist."

    with open(SUMMARY_LOG, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_sorted = sorted(EXPECTED_FILES)
    assert lines == expected_sorted, (
        f"Summary log contents do not match expected sorted filenames.\n"
        f"Expected: {expected_sorted}\n"
        f"Found: {lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
