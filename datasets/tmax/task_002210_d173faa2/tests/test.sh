#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/telemetry_svc")
BINARY = PROJECT / "parser_svc"
INPUT = Path("/home/user/sensor_data.csv")
OUTPUT = Path("/home/user/clean_data.csv")
POSTMORTEM = Path("/home/user/postmortem.txt")


@pytest.fixture(scope="session", autouse=True)
def build_and_run(tmp_path_factory):
    # Remove stale build products so a successful test requires make to rebuild.
    for artifact in list(PROJECT.glob("*.o")) + [BINARY]:
        try:
            artifact.unlink()
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["make"], cwd=PROJECT, text=True, capture_output=True, timeout=30
    )
    assert build.returncode == 0, (
        f"make failed with exit code {build.returncode}\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert BINARY.is_file(), "make did not produce parser_svc"
    assert os.access(BINARY, os.X_OK), "parser_svc is not executable"
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "parser_svc is not a compiled ELF binary"

    # Run the exact command required by the task, replacing any hand-written output.
    run = subprocess.run(
        [str(BINARY), str(INPUT), str(OUTPUT)],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert run.returncode == 0, (
        f"parser_svc crashed or failed on sensor_data.csv (exit {run.returncode})\n"
        f"stdout:\n{run.stdout}\nstderr:\n{run.stderr}"
    )

    # Exercise the built program on unpredictable high-precision timestamps and
    # both populated and empty status fields.
    dynamic_dir = tmp_path_factory.mktemp("dynamic_parser_test")
    dynamic_input = dynamic_dir / "input.csv"
    dynamic_output = dynamic_dir / "output.csv"
    base = 1_700_000_000_000_000 + secrets.randbelow(50_000_000)
    records = [
        [701, base + 11, "12.3", "OK"],
        [702, base + 1237, "0.4", "WARN"],
        [703, base + 98765, "91.7", ""],
        [704, base + 7654321, "5.0", "OK"],
    ]
    with dynamic_input.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["ID", "TIMESTAMP", "VALUE", "STATUS"])
        writer.writerows(records)

    dynamic_run = subprocess.run(
        [str(BINARY), str(dynamic_input), str(dynamic_output)],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert dynamic_run.returncode == 0, (
        f"parser_svc failed on generated input (exit {dynamic_run.returncode})\n"
        f"stdout:\n{dynamic_run.stdout}\nstderr:\n{dynamic_run.stderr}"
    )
    assert dynamic_output.is_file(), "parser_svc did not create its requested output"

    with dynamic_output.open(newline="") as f:
        rows = list(csv.reader(f))
    assert rows[0] == ["ID", "TIMESTAMP", "VALUE", "STATUS"]
    assert rows[1:] == [[str(v) for v in row] for row in records], (
        "Generated data was not parsed correctly; IDs, values, statuses, and exact "
        "microsecond timestamps must all be preserved"
    )


def test_binary_exists_and_executable():
    binary_path = str(BINARY)
    assert os.path.isfile(binary_path), f"Binary {binary_path} was not built."
    assert os.access(binary_path, os.X_OK), f"File {binary_path} is not executable."


def test_postmortem_exists():
    pm_path = str(POSTMORTEM)
    assert os.path.isfile(pm_path), f"Post-mortem file {pm_path} does not exist."
    assert os.path.getsize(pm_path) > 0, f"Post-mortem file {pm_path} is empty."

    text = POSTMORTEM.read_text(errors="replace").lower()
    assert re.search(r"(?:-lm|libm|math\s+library)", text), (
        "Post-mortem must describe the missing math-library linker flag."
    )
    assert ("null" in text or "null pointer" in text) and any(
        word in text for word in ("status", "token", "strtok")
    ), "Post-mortem must describe the format-parser null dereference."
    assert "float" in text and any(
        term in text for term in ("uint64_t", "uint64", "64-bit", "64 bit", "unsigned long")
    ), "Post-mortem must identify the timestamp variable type that caused precision loss."


def test_clean_data_correctness():
    output_path = str(OUTPUT)
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. Did you run the binary?"

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 5, "Output file does not contain all expected rows (header + 4 data rows). The program might have crashed."
    assert "TIMESTAMP" in lines[0], "Header row is missing or incorrect."

    expected_timestamps = [
        "1700000000123456",
        "1700000000223456",
        "1700000000323456",
        "1700000000423456",
    ]
    extracted_timestamps = []
    for line in lines[1:]:
        parts = line.split(",")
        if len(parts) >= 2:
            extracted_timestamps.append(parts[1])
    for expected in expected_timestamps:
        assert expected in extracted_timestamps, f"Expected timestamp {expected} not found in output. Precision loss bug is likely not fixed."

    with OUTPUT.open(newline="") as f:
        rows = list(csv.reader(f))
    assert rows == [
        ["ID", "TIMESTAMP", "VALUE", "STATUS"],
        ["101", "1700000000123456", "42.5", "OK"],
        ["102", "1700000000223456", "43.1", "OK"],
        ["103", "1700000000323456", "41.9", ""],
        ["104", "1700000000423456", "44.2", "OK"],
    ], "clean_data.csv does not contain the correctly parsed IDs, values, statuses, and timestamps"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
