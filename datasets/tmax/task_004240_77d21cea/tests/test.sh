#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess

SOURCE_PATH = "/home/user/seq_sim.c"
STRICT_PATH = "/home/user/seq_strict"
FAST_PATH = "/home/user/seq_fast"
MAX_DIFF_PATH = "/home/user/max_diff.txt"
WORKDIR = "/tmp/verifier_seq_check"

CANONICAL_SOURCE = b'''#include <stdio.h>
#include <stdlib.h>

int main() {
    int n = 30000000;
    float pA = 0.0f, pC = 0.0f, pG = 0.0f, pT = 0.0f;
    srand(12345);
    for(int i = 0; i < n; i++) {
        pA += (float)(rand() % 100) / 100000000.0f;
        pC += (float)(rand() % 100) / 100000000.0f;
        pG += (float)(rand() % 100) / 100000000.0f;
        pT += (float)(rand() % 100) / 100000000.0f;
    }
    float total = pA + pC + pG + pT;
    printf("A: %.8f\\n", pA/total);
    printf("C: %.8f\\n", pC/total);
    printf("G: %.8f\\n", pG/total);
    printf("T: %.8f\\n", pT/total);
    return 0;
}
'''


def parse_distribution(output):
    lines = output.strip().splitlines()
    assert len(lines) == 4, f"Expected exactly four output lines, got {lines!r}"
    result = {}
    for expected_label, line in zip(("A", "C", "G", "T"), lines):
        match = re.fullmatch(r"([ACGT]):\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)", line)
        assert match, f"Malformed simulator output line: {line!r}"
        assert match.group(1) == expected_label, f"Expected {expected_label}, got {line!r}"
        result[expected_label] = float(match.group(2))
    return result


def prepare_reference():
    shutil.rmtree(WORKDIR, ignore_errors=True)
    os.mkdir(WORKDIR, 0o700)

    with open(os.path.join(WORKDIR, "seq_sim.c"), "wb") as f:
        f.write(CANONICAL_SOURCE)

    # Snapshot the submitted artifacts before testing them.
    submitted_strict = os.path.join(WORKDIR, "submitted_strict")
    submitted_fast = os.path.join(WORKDIR, "submitted_fast")
    shutil.copyfile(STRICT_PATH, submitted_strict)
    shutil.copyfile(FAST_PATH, submitted_fast)
    os.chmod(submitted_strict, 0o700)
    os.chmod(submitted_fast, 0o700)

    truth_strict = os.path.join(WORKDIR, "truth_strict")
    truth_fast = os.path.join(WORKDIR, "truth_fast")
    source = os.path.join(WORKDIR, "seq_sim.c")
    subprocess.run(["gcc", "-O0", source, "-o", truth_strict], check=True)
    subprocess.run(["gcc", "-O3", "-ffast-math", source, "-o", truth_fast], check=True)

    return submitted_strict, submitted_fast, truth_strict, truth_fast


def run_program(path):
    completed = subprocess.run(
        [path], capture_output=True, text=True, check=True, timeout=120
    )
    assert completed.stderr == "", f"{path} wrote unexpected stderr: {completed.stderr!r}"
    return parse_distribution(completed.stdout)


def test_executables_exist():
    """Test that the required executables were created and are executable."""
    assert os.path.isfile(STRICT_PATH), f"The executable {STRICT_PATH} does not exist."
    assert os.access(STRICT_PATH, os.X_OK), f"The file {STRICT_PATH} is not executable."
    assert os.path.isfile(FAST_PATH), f"The executable {FAST_PATH} does not exist."
    assert os.access(FAST_PATH, os.X_OK), f"The file {FAST_PATH} is not executable."

    with open(STRICT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{STRICT_PATH} is not an ELF executable"
    with open(FAST_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{FAST_PATH} is not an ELF executable"


def test_source_is_original():
    assert os.path.isfile(SOURCE_PATH), f"The source file {SOURCE_PATH} does not exist."
    with open(SOURCE_PATH, "rb") as f:
        assert f.read() == CANONICAL_SOURCE, f"{SOURCE_PATH} was modified"


def test_max_diff_correct():
    """Run the submitted builds and verify their flags, outputs, and reported difference."""
    assert os.path.isfile(MAX_DIFF_PATH), f"The file {MAX_DIFF_PATH} does not exist."

    submitted_strict, submitted_fast, truth_strict, truth_fast = prepare_reference()

    # Deterministic GCC output must match builds made from the original source with
    # the exact required optimization options. This rejects executable placeholders
    # and builds made with the wrong flags.
    with open(submitted_strict, "rb") as f:
        submitted_strict_bytes = f.read()
    with open(truth_strict, "rb") as f:
        truth_strict_bytes = f.read()
    assert submitted_strict_bytes == truth_strict_bytes, (
        f"{STRICT_PATH} is not the gcc -O0 build of the original source"
    )

    with open(submitted_fast, "rb") as f:
        submitted_fast_bytes = f.read()
    with open(truth_fast, "rb") as f:
        truth_fast_bytes = f.read()
    assert submitted_fast_bytes == truth_fast_bytes, (
        f"{FAST_PATH} is not the gcc -O3 -ffast-math build of the original source"
    )

    # Actually execute both submitted artifacts and independently built truth artifacts.
    submitted_strict_dist = run_program(submitted_strict)
    submitted_fast_dist = run_program(submitted_fast)
    truth_strict_dist = run_program(truth_strict)
    truth_fast_dist = run_program(truth_fast)

    assert submitted_strict_dist == truth_strict_dist
    assert submitted_fast_dist == truth_fast_dist

    # Preserve the original independent recomputation of the expected result.
    max_diff = max(
        abs(truth_strict_dist[label] - truth_fast_dist[label])
        for label in ("A", "C", "G", "T")
    )
    expected_diff_str = f"{max_diff:.8f}"

    with open(MAX_DIFF_PATH, "r") as f:
        actual_contents = f.read()
    actual_diff_str = actual_contents.strip()

    assert actual_diff_str == expected_diff_str, (
        f"Incorrect value in {MAX_DIFF_PATH}. "
        f"Expected {expected_diff_str}, but got {actual_diff_str!r}."
    )
    assert re.fullmatch(r"\d+\.\d{8}\n?", actual_contents), (
        f"{MAX_DIFF_PATH} must contain only one value formatted to exactly 8 decimal places"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
