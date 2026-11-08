#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
from pathlib import Path

import pytest

BASE = Path("/home/user/sim_profiling")
EXECUTABLE = BASE / "sim_fixed"
SOURCE = BASE / "simulation.c"
DATASET = BASE / "sensor_data.txt"
RESULT = BASE / "final_result.txt"


def expected_output(lines):
    total = 0.0
    for line in lines:
        text = line.strip()
        if not text:
            continue
        try:
            value = float(text)
        except ValueError:
            continue
        total += value
    return f"Total Sum: {total:.4f}\n"


def run_program(program, cwd):
    completed = subprocess.run(
        [str(program)],
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert completed.returncode == 0, (
        f"{program} exited with status {completed.returncode}. "
        f"stderr: {completed.stderr!r}"
    )
    return completed.stdout


def test_sim_fixed_executable_exists():
    """Check that sim_fixed is an executable produced in compiled-binary form."""
    assert EXECUTABLE.is_file(), f"Executable {EXECUTABLE} does not exist. Did you compile the code?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with EXECUTABLE.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "sim_fixed is not a gcc-compiled ELF executable."


def test_final_result_exists_and_correct():
    """Check final_result against the sum derived from all valid dataset lines."""
    assert RESULT.is_file(), f"Result file {RESULT} does not exist. Did you run the executable and redirect output?"
    lines = DATASET.read_text().splitlines()
    expected = expected_output(lines)
    content = RESULT.read_text().strip()
    assert content == expected.strip(), f"Expected output {expected.strip()!r}, but got {content!r}."

    actual = run_program(EXECUTABLE, BASE)
    assert actual == expected, "sim_fixed does not produce the required output on sensor_data.txt."
    assert content == actual.strip(), "final_result.txt is not the output produced by sim_fixed."


def test_simulation_c_modified():
    """Keep the source-level double-precision assertion."""
    assert SOURCE.is_file(), f"Source file {SOURCE} is missing."
    content = SOURCE.read_text()
    assert "double " in content, (
        "The source code does not appear to use 'double' precision. "
        "You must use double for the accumulation to avoid precision loss."
    )


@pytest.fixture(scope="module")
def rebuilt_program(tmp_path_factory):
    """Compile the submitted source independently so its behavior is also verified."""
    build_dir = tmp_path_factory.mktemp("build")
    output = build_dir / "rebuilt_sim"
    completed = subprocess.run(
        ["gcc", "-std=c11", "-O2", str(SOURCE), "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    assert completed.returncode == 0, f"simulation.c does not compile with gcc: {completed.stderr}"
    return output


def exercise(program, lines):
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        (work / "sensor_data.txt").write_text("\n".join(lines) + "\n")
        return run_program(program, work)


@pytest.mark.parametrize("lines", [
    ["1.25", "CORRUPTED", "-0.50", "2.00"],
    ["BAD_FIRST", "0.1", "0.2", "BAD_MIDDLE", "0.3", "BAD_LAST"],
    ["100000000"] + ["0.1"] * 1000 + ["NOT_A_READING"],
])
def test_binary_handles_derived_inputs(lines):
    assert exercise(EXECUTABLE, lines) == expected_output(lines)


@pytest.mark.parametrize("lines", [
    ["1.25", "CORRUPTED", "-0.50", "2.00"],
    ["BAD_FIRST", "0.1", "0.2", "BAD_MIDDLE", "0.3", "BAD_LAST"],
    ["100000000"] + ["0.1"] * 1000 + ["NOT_A_READING"],
])
def test_submitted_source_handles_derived_inputs(rebuilt_program, lines):
    assert exercise(rebuilt_program, lines) == expected_output(lines)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
