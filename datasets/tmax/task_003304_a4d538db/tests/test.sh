#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import re
import subprocess

PROJECT = "/home/user/rpn_calc"
EXE = os.path.join(PROJECT, "calc")


def run_calc(expression):
    result = subprocess.run(
        [EXE],
        input=(expression + "\n").encode(),
        capture_output=True,
        timeout=5,
    )
    assert result.returncode == 0, f"calc exited with status {result.returncode}: {result.stderr.decode(errors='replace')}"
    return result.stdout.decode("utf-8")


def test_patch_applied():
    """Check that the patch was applied by verifying math_ops.c exists."""
    path = os.path.join(PROJECT, "math_ops.c")
    assert os.path.exists(path), "math_ops.c does not exist. The patch was not applied."
    assert os.path.isfile(path) and os.path.getsize(path) > 0, "math_ops.c is empty or not a regular file."


def test_makefile_fixed():
    """Check that Makefile was fixed to link math_ops.o."""
    path = os.path.join(PROJECT, "Makefile")
    assert os.path.exists(path), "Makefile is missing."
    with open(path, "r") as f:
        lines = f.readlines()

    linked_correctly = False
    for i, line in enumerate(lines):
        if line.startswith("calc:"):
            if i + 1 < len(lines) and "math_ops.o" in lines[i + 1]:
                linked_correctly = True
                break

    assert linked_correctly, "Makefile does not correctly link math_ops.o in the 'calc' target."


def test_clean_rebuild_from_sources():
    """Require make to recreate the executable and objects from the submitted sources."""
    for path in glob.glob(os.path.join(PROJECT, "*.o")) + [EXE]:
        if os.path.lexists(path):
            os.unlink(path)

    result = subprocess.run(
        ["make"], cwd=PROJECT, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"

    math_obj = os.path.join(PROJECT, "math_ops.o")
    assert os.path.isfile(math_obj), "make did not compile math_ops.c into math_ops.o."
    assert open(math_obj, "rb").read(4) == b"\x7fELF", "math_ops.o is not a compiled ELF object."

    symbols = subprocess.run(
        ["nm", "-g", math_obj], capture_output=True, text=True, timeout=5, check=True
    ).stdout
    assert re.search(r"\bT\s+factorial$", symbols, re.MULTILINE), "math_ops.o does not define factorial()."


def test_executable_exists():
    """Check that the calc executable exists and is executable."""
    assert os.path.isfile(EXE), "The compiled 'calc' executable does not exist."
    assert os.access(EXE, os.X_OK), "The 'calc' file is not executable."
    assert open(EXE, "rb").read(4) == b"\x7fELF", "The compiled 'calc' is not an ELF executable."

    symbols = subprocess.run(
        ["nm", "-g", EXE], capture_output=True, text=True, timeout=5, check=True
    ).stdout
    assert re.search(r"\bT\s+factorial$", symbols, re.MULTILINE), "calc was not linked with factorial() from math_ops.o."


def test_executable_behavior():
    """Exercise factorial on several inputs and derive all expected answers."""
    output = run_calc("6 ! P").strip()
    assert output == "720", f"The compiled calculator produced incorrect output for 6!: expected '720', got '{output}'. The logical error in math_ops.c may not be fixed."

    values = [2, 3, 5, 7, 9]
    expression = " ".join(f"{n} ! P" for n in values)
    actual = run_calc(expression).splitlines()
    expected = [str(math.factorial(n)) for n in values]
    assert actual == expected, f"Factorial results were incorrect: expected {expected}, got {actual}."

    combined = run_calc("3 4 + ! P").splitlines()
    expected_combined = [str(math.factorial(3 + 4))]
    assert combined == expected_combined, f"Factorial did not integrate correctly with stack operations: expected {expected_combined}, got {combined}."


def test_calc_output():
    """Check that calc_out.txt is the exact output produced for 5!."""
    out_file = "/home/user/calc_out.txt"
    assert os.path.exists(out_file), f"{out_file} does not exist."

    with open(out_file, "r") as f:
        content = f.read().strip()
    assert content == "120", f"Expected {out_file} to contain '120', but got '{content}'."

    with open(out_file, "rb") as f:
        raw_content = f.read()
    live_output = run_calc("5 ! P").encode()
    assert raw_content == live_output == b"120\n", "calc_out.txt is not the exact output of the rebuilt calculator for '5 ! P'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
