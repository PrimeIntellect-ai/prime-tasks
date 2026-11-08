#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import importlib.machinery
import os
import re
import subprocess
import sys
import sysconfig

import pytest

HOME = "/home/user"


@pytest.fixture(scope="session", autouse=True)
def build_and_validate_extension():
    """Perform a clean build and ensure it produces a working C extension."""
    subprocess.run(["rm", "-rf", os.path.join(HOME, "build")], check=True)
    for path in glob.glob(os.path.join(HOME, "fast_math*.so")):
        os.remove(path)

    result = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, "Extension build failed:\n" + result.stdout

    suffix = sysconfig.get_config_var("EXT_SUFFIX")
    assert suffix, "Could not determine Python extension suffix"
    artifacts = glob.glob(os.path.join(HOME, "fast_math*" + suffix))
    assert artifacts, "The build did not produce an in-place fast_math extension"
    assert any(open(path, "rb").read(4) == b"\x7fELF" for path in artifacts), \
        "fast_math build artifact is not an ELF shared object"

    probe = subprocess.run(
        [sys.executable, "-c", """
import math
import fast_math
assert any(fast_math.__file__.endswith(s) for s in __import__('importlib').machinery.EXTENSION_SUFFIXES)
assert fast_math.calc(9.0, 5.0) == 2.0
assert math.isnan(fast_math.calc(1.0, 2.0))
"""],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert probe.returncode == 0, "Built fast_math extension could not be imported or used:\n" + probe.stdout


def test_report_exists_and_format():
    """Verify that report.txt exists and contains the correct answers."""
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"Missing required file: {report_path}"
    assert os.path.isfile(report_path), f"Expected a file, but found something else: {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip()

    missing_library_match = re.search(r"Missing library:\s*(.+)", content)
    failing_row_match = re.search(r"Failing row index:\s*(\d+)", content)

    assert missing_library_match is not None, "Could not find 'Missing library: <name>' in report.txt"
    assert failing_row_match is not None, "Could not find 'Failing row index: <integer>' in report.txt"

    missing_library = missing_library_match.group(1).strip()
    failing_row = int(failing_row_match.group(1).strip())

    assert missing_library == "m", f"Expected missing library to be 'm', but got '{missing_library}'"
    assert failing_row == 682, f"Expected failing row index to be 682, but got {failing_row}"


def test_setup_py_fixed():
    """Verify that setup.py was modified to include the missing library."""
    setup_path = "/home/user/setup.py"
    assert os.path.exists(setup_path), f"Missing {setup_path}"

    with open(setup_path, "r") as f:
        content = f.read()

    assert re.search(r"libraries\s*=\s*\[\s*['\"]m['\"]\s*\]", content) is not None, \
        "setup.py does not appear to have libraries=['m'] added."


def test_process_data_isolates_actual_bad_row():
    """Derive the unstable row from the data and exercise process_data.py ranges."""
    with open(os.path.join(HOME, "data.csv"), newline="") as f:
        rows = [(float(x), float(y)) for x, y in csv.reader(f)]

    bad_rows = [i for i, (x, y) in enumerate(rows) if x < y]
    assert bad_rows == [682], f"Unexpected unstable rows in data.csv: {bad_rows}"
    bad = bad_rows[0]

    def run(start, end):
        return subprocess.run(
            [sys.executable, os.path.join(HOME, "process_data.py"), str(start), str(end)],
            cwd=HOME,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )

    before = run(0, bad)
    assert before.returncode == 0, before.stdout + before.stderr

    isolated = run(bad, bad + 1)
    assert isolated.returncode != 0, "The isolated unstable row did not fail"
    assert "ValueError: Numerical instability detected in batch!" in isolated.stderr

    after = run(bad + 1, len(rows))
    assert after.returncode == 0, after.stdout + after.stderr

    full = run(0, len(rows))
    assert full.returncode != 0, "Processing the full dataset unexpectedly succeeded"
    assert "ValueError: Numerical instability detected in batch!" in full.stderr
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
