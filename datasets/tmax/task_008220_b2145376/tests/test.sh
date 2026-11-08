#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path("/home/user/run_and_profile.sh")
OBS = Path("/home/user/obs.csv")
APP = Path("/home/user/app.py")
INPUT = Path("/home/user/input.txt")
PROFILE = Path("/home/user/profile.txt")
BOTTLENECK = Path("/home/user/bottleneck.txt")

CANONICAL_OBS = """1.0,2.0,3.0
4.0,5.0,6.0
7.0,8.0,9.0
"""

CANONICAL_APP = """import sys
import numpy as np

def solve_pde(data):
    # Inefficient PDE step to guarantee it dominates tottime
    u = np.array(data)
    for _ in range(5000):
        temp = np.zeros_like(u)
        for i in range(len(u)):
            temp[i] = u[i] * 1.0001
        u = temp
    return u

def compute_distance(u, target):
    # Dummy distance metric (L1)
    return np.sum(np.abs(u - target))

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    with open(sys.argv[1], 'r') as f:
        data = [float(x) for x in f.read().split()]
    u = solve_pde(data)
    target = np.ones_like(u)
    dist = compute_distance(u, target)
    print(f"Distance: {dist}")

if __name__ == '__main__':
    main()
"""

ROW_RE = re.compile(
    r"^\s*(\d+(?:/\d+)?)\s+([0-9]+(?:\.[0-9]+)?)\s+"
    r"([0-9]+(?:\.[0-9]+)?)\s+([0-9]+(?:\.[0-9]+)?)\s+"
    r"([0-9]+(?:\.[0-9]+)?)\s+(.+?)\s*$"
)


def run_submission():
    for path in (INPUT, PROFILE, BOTTLENECK):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Script failed to execute properly. stdout: {result.stdout}\n"
        f"stderr: {result.stderr}"
    )


def read_profile_rows():
    assert PROFILE.is_file(), f"File {PROFILE} does not exist."
    content = PROFILE.read_text()
    assert "tottime" in content, "profile.txt does not appear to contain cProfile output sorted by tottime."
    assert re.search(r"\d+ function calls.* in [0-9]+(?:\.[0-9]+)? seconds", content), (
        "profile.txt is missing the cProfile call-count summary."
    )
    assert re.search(
        r"ncalls\s+tottime\s+percall\s+cumtime\s+percall\s+filename:lineno\(function\)",
        content,
    ), "profile.txt is missing the standard cProfile statistics header."

    rows = []
    for line in content.splitlines():
        match = ROW_RE.match(line)
        if match:
            rows.append((match.group(1), float(match.group(2)), match.group(6)))
    assert rows, "profile.txt contains no parseable cProfile statistics rows."
    assert all(rows[i][1] >= rows[i + 1][1] for i in range(len(rows) - 1)), (
        "profile.txt statistics are not sorted by descending tottime."
    )
    return content, rows


def assert_bottleneck_matches_profile(rows):
    assert BOTTLENECK.is_file(), f"File {BOTTLENECK} does not exist."
    value = BOTTLENECK.read_text().strip()
    assert value == rows[0][2], (
        f"bottleneck.txt must contain the final column of the first profile row; "
        f"expected {rows[0][2]!r}, got {value!r}."
    )
    assert len(BOTTLENECK.read_text().splitlines()) == 1, "bottleneck.txt must contain only one identifier."
    return value


def test_script_exists_and_executable():
    assert SCRIPT.is_file(), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_run_script_and_check_outputs():
    old_obs = OBS.read_bytes() if OBS.exists() else None
    old_app = APP.read_bytes() if APP.exists() else None
    try:
        # Preserve all checks made by the original verifier on the supplied files.
        OBS.write_text(CANONICAL_OBS)
        APP.write_text(CANONICAL_APP)
        run_submission()

        assert INPUT.is_file(), f"File {INPUT} does not exist."
        normalized_input = " ".join(INPUT.read_text().strip().split())
        expected_input = "1.0 4.0 7.0 2.0 5.0 8.0 3.0 6.0 9.0"
        assert normalized_input == expected_input, (
            f"Expected input.txt to be {expected_input!r}, got {normalized_input!r}."
        )

        profile_content, rows = read_profile_rows()
        assert "solve_pde" in profile_content, "profile.txt does not contain expected function names."
        bottleneck = assert_bottleneck_matches_profile(rows)
        assert bottleneck == "app.py:4(solve_pde)", (
            "Expected bottleneck.txt to contain 'app.py:4(solve_pde)', "
            f"got {bottleneck!r}."
        )

        # Exercise the pipeline again with unpredictable data and an unpredictable
        # hot-function identifier. The application writes its marker only while an
        # active profiler is installed, proving that it was actually profiled.
        values = [f"{secrets.randbelow(8000) + 1000}.{secrets.randbelow(1000):03d}" for _ in range(9)]
        OBS.write_text("\n".join(",".join(values[r * 3:(r + 1) * 3]) for r in range(3)) + "\n")
        expected_dynamic = " ".join(values[r * 3 + c] for c in range(3) for r in range(3))

        hot_name = "profile_hot_" + secrets.token_hex(6)
        marker = Path("/tmp/profile_marker_" + secrets.token_hex(8))
        token = secrets.token_hex(16)
        padding = "\n".join("# randomized line padding" for _ in range(secrets.randbelow(8) + 2))
        dynamic_app = f'''import sys
from pathlib import Path
{padding}
def {hot_name}(data):
    total = 0.0
    size = len(data)
    for i in range(900000):
        total += data[i % size] * 0.000001
    return total

def main():
    expected = {expected_dynamic!r}
    actual = Path(sys.argv[1]).read_text().strip()
    if " ".join(actual.split()) != expected:
        raise SystemExit(41)
    data = [float(x) for x in actual.split()]
    result = {hot_name}(data)
    if sys.getprofile() is None:
        raise SystemExit(42)
    Path({str(marker)!r}).write_text({token!r})
    print(result)

if __name__ == "__main__":
    main()
'''
        APP.write_text(dynamic_app)
        hot_line = next(
            i for i, line in enumerate(dynamic_app.splitlines(), 1)
            if line.startswith(f"def {hot_name}(")
        )
        try:
            marker.unlink()
        except FileNotFoundError:
            pass

        run_submission()
        assert " ".join(INPUT.read_text().strip().split()) == expected_dynamic, (
            "input.txt was not produced by transposing and row-wise flattening the current obs.csv."
        )
        assert marker.is_file() and marker.read_text() == token, (
            "The application did not run while a Python profiler was active."
        )

        dynamic_content, dynamic_rows = read_profile_rows()
        dynamic_bottleneck = assert_bottleneck_matches_profile(dynamic_rows)
        expected_suffix = f"app.py:{hot_line}({hot_name})"
        assert dynamic_bottleneck.endswith(expected_suffix), (
            f"Expected the measured hot function {expected_suffix!r} to be first by tottime, "
            f"got {dynamic_bottleneck!r}."
        )
        assert hot_name in dynamic_content
    finally:
        if old_obs is None:
            OBS.unlink(missing_ok=True)
        else:
            OBS.write_bytes(old_obs)
        if old_app is None:
            APP.unlink(missing_ok=True)
        else:
            APP.write_bytes(old_app)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
