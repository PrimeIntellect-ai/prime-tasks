#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from decimal import Decimal

import pytest

PROJECT = "/home/user/astro_calc"
SOURCE = os.path.join(PROJECT, "calc.c")
MAKEFILE = os.path.join(PROJECT, "Makefile")
EXECUTABLE = os.path.join(PROJECT, "astro_calc")
OUTPUT = "/home/user/fixed_output.txt"
EXPECTED_TEXT = "Trajectory: 140.4304968"
EXPECTED_BYTES = b"Trajectory: 140.4304968\n"


@pytest.fixture(scope="session", autouse=True)
def rebuild_project():
    """Require the submitted Makefile to perform a fresh successful build."""
    assert os.path.isfile(MAKEFILE), f"Expected Makefile {MAKEFILE} does not exist."
    assert os.path.isfile(SOURCE), f"Expected source file {SOURCE} does not exist."

    dry_run = subprocess.run(
        ["make", "-B", "-n"], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert dry_run.returncode == 0, f"Makefile dry run failed:\n{dry_run.stdout}{dry_run.stderr}"
    assert "-lm" in dry_run.stdout + dry_run.stderr, "The effective Makefile build command does not link libm with -lm."

    if os.path.lexists(EXECUTABLE):
        os.remove(EXECUTABLE)

    build = subprocess.run(
        ["make", "-B"], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f"Fresh make build failed:\n{build.stdout}{build.stderr}"


def test_source_restores_precision():
    """Check the requested high-precision constant and double calculations."""
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    constant = re.search(
        r"^\s*#\s*define\s+CALIBRATION_SECRET\s+([0-9]+\.([0-9]+))\s*$",
        source,
        re.MULTILINE,
    )
    assert constant, "CALIBRATION_SECRET must be defined as a decimal constant."
    assert len(constant.group(2)) >= 10, "CALIBRATION_SECRET is still truncated."
    assert Decimal(constant.group(1)) == Decimal("8.9875517923"), "The original calibration secret was not restored."

    assert not re.search(r"\bfloat\b", source), "calc.c still uses float and loses precision."
    assert not re.search(r"\bpowf\s*\(", source), "calc.c still uses the float powf calculation."
    declared_as_double = set(re.findall(r"\bdouble\s+(input|intermediate|result)\b", source))
    assert declared_as_double == {"input", "intermediate", "result"}, "input, intermediate, and result must all use double."


def test_fixed_output_exists():
    """Check if the expected output file exists."""
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."


def test_fixed_output_content():
    """Retain the original exact expected trajectory assertion."""
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_TEXT, f"Output file content is incorrect. Expected '{EXPECTED_TEXT}', got '{content}'."


def test_executable_exists():
    """Check if the freshly compiled executable exists and is a native binary."""
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} does not exist. Ensure the project was compiled."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "astro_calc is not a compiled ELF executable."


def test_executable_produces_submitted_output():
    """Actually execute astro_calc and verify fixed_output is its exact stdout."""
    run = subprocess.run(
        [EXECUTABLE], cwd=PROJECT, capture_output=True, timeout=5
    )
    assert run.returncode == 0, f"astro_calc exited with status {run.returncode}: {run.stderr!r}"
    assert run.stdout == EXPECTED_BYTES, f"astro_calc produced incorrect stdout: {run.stdout!r}"
    with open(OUTPUT, "rb") as f:
        submitted = f.read()
    assert submitted == run.stdout, "fixed_output.txt is not exactly the stdout produced by astro_calc."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
