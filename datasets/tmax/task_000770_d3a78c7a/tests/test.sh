#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import tempfile

import pytest

REPORT_PATH = "/home/user/fix_report.json"
BINARY_PATH = "/home/user/engine/process"
SOURCE_PATH = "/home/user/engine/process.c"
BUILD_PATH = "/home/user/engine/build.sh"
INPUT_PATH = "/home/user/engine/input.txt"


def run_processor(binary, input_path):
    return subprocess.run(
        [binary, input_path], capture_output=True, timeout=10, check=False
    )


def assert_processed_count(binary, input_path, expected):
    res = run_processor(binary, input_path)
    assert res.returncode == 0, (
        f"{binary} failed with return code {res.returncode}. "
        f"Stderr: {res.stderr.decode(errors='replace')}"
    )
    stdout = res.stdout.decode(errors="replace")
    match = re.search(r"Successfully processed\s+(\d+)\s+lines", stdout)
    assert match, f"Processor did not report a processed-line count. Stdout: {stdout!r}"
    assert int(match.group(1)) == expected, (
        f"Expected {expected} processed lines, got {match.group(1)}. Stdout: {stdout!r}"
    )


def test_report_exists_and_valid():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("fix_report.json is not valid JSON")

    assert "crashing_line_index" in report, "Missing 'crashing_line_index' in report"
    assert "fixed_binary_path" in report, "Missing 'fixed_binary_path' in report"
    assert report["crashing_line_index"] == 421, (
        f"Expected crashing_line_index 421, got {report['crashing_line_index']}"
    )
    assert report["fixed_binary_path"] == BINARY_PATH, (
        f"Expected fixed_binary_path {BINARY_PATH}, got {report['fixed_binary_path']}"
    )


def test_original_input_and_binary_runs_successfully():
    assert os.path.isfile(BINARY_PATH), f"Binary {BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."
    assert os.path.isfile(INPUT_PATH), f"Input file {INPUT_PATH} does not exist."

    with open(INPUT_PATH, "r") as f:
        lines = f.readlines()
    assert len(lines) == 1000, f"Expected input.txt to contain 1000 lines, got {len(lines)}"
    assert lines[421].split() == ["1000.0001", "1000.0000", "500.0"], (
        "The known crashing line in input.txt was altered"
    )

    res = run_processor(BINARY_PATH, INPUT_PATH)
    assert res.returncode == 0, (
        f"Binary failed with return code {res.returncode}. "
        f"Stderr: {res.stderr.decode(errors='replace')}"
    )
    stdout = res.stdout.decode(errors="replace")
    assert "1000" in stdout, (
        f"Binary did not seem to process all 1000 lines. Stdout: {stdout}"
    )
    assert_processed_count(BINARY_PATH, INPUT_PATH, 1000)


def test_artifacts_are_real_and_source_builds(tmp_path):
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} does not exist."
    assert os.path.isfile(BUILD_PATH), f"Build script {BUILD_PATH} does not exist."
    assert os.access(BUILD_PATH, os.X_OK), f"Build script {BUILD_PATH} is not executable."

    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "process must be a compiled ELF binary, not a script"

    rebuilt = tmp_path / "process_from_source"
    build = subprocess.run(
        ["gcc", "-g", "-O0", SOURCE_PATH, "-o", str(rebuilt)],
        capture_output=True,
        timeout=20,
        check=False,
    )
    assert build.returncode == 0, (
        "process.c does not compile successfully: "
        + build.stderr.decode(errors="replace")
    )
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    # Exercise both the submitted binary and a fresh build of the submitted source
    # on runtime-generated inputs with varying sizes and poison lines.
    rng = random.SystemRandom()
    for count in (1, rng.randint(9, 31), rng.randint(73, 149)):
        poison_index = rng.randrange(count)
        test_input = tmp_path / f"generated_{count}_{poison_index}.txt"
        rows = []
        for i in range(count):
            if i == poison_index:
                base = rng.randint(700, 5000)
                rows.append(f"{base}.0001 {base}.0000 {rng.randint(200, 900)}.0\n")
            else:
                a = rng.uniform(20.0, 60.0)
                b = rng.uniform(1.0, 5.0)
                c = rng.uniform(100.0, 500.0)
                rows.append(f"{a:.6f} {b:.6f} {c:.6f}\n")
        test_input.write_text("".join(rows))

        assert_processed_count(BINARY_PATH, str(test_input), count)
        assert_processed_count(str(rebuilt), str(test_input), count)

    empty_input = tmp_path / "empty.txt"
    empty_input.write_text("")
    assert_processed_count(BINARY_PATH, str(empty_input), 0)
    assert_processed_count(str(rebuilt), str(empty_input), 0)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
