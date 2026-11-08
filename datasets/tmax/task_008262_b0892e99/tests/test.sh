#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import datetime
import importlib.util
import math
import os
import random
import subprocess


def load_submission():
    jd_file = "/home/user/astro_calc/jd.py"
    assert os.path.isfile(jd_file), f"{jd_file} does not exist"
    spec = importlib.util.spec_from_file_location("submitted_jd", jd_file)
    assert spec is not None and spec.loader is not None, "Could not load jd.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "get_julian_date", None)), "jd.py does not define callable get_julian_date"
    return module


def expected_julian_date(dt):
    epoch = datetime.datetime(1970, 1, 1)
    return 2440587.5 + (dt - epoch).total_seconds() / 86400.0


def test_bug_commit_hash():
    # Retrieve the actual buggy commit hash from git history
    result = subprocess.run(
        ["git", "log", "--grep=Refactor JD calculation for performance", "--format=%H"],
        cwd="/home/user/astro_calc",
        capture_output=True,
        text=True,
        check=True
    )
    expected_hash = result.stdout.strip()
    assert expected_hash, "Could not find the buggy commit in git history"

    bug_commit_file = "/home/user/bug_commit.txt"
    assert os.path.isfile(bug_commit_file), f"{bug_commit_file} does not exist"

    with open(bug_commit_file, "r") as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"Expected buggy commit hash {expected_hash}, but found {actual_hash}"


def test_secret_recovered():
    secret_file = "/home/user/secret.txt"
    assert os.path.isfile(secret_file), f"{secret_file} does not exist"

    with open(secret_file, "r") as f:
        secret = f.read().strip()

    assert secret == "7b9a2c8f-3e1d-4a5b-8c2e-1d9f4a5b8c2e", "The recovered secret token is incorrect"


def test_jd_output():
    output_file = "/home/user/jd_output.txt"
    assert os.path.isfile(output_file), f"{output_file} does not exist"

    with open(output_file, "r") as f:
        output = f.read().strip()

    # The expected output is 2460311.0 for 2024-01-01 12:00:00
    assert output == "2460311.0", f"Expected JD output to be 2460311.0, but got {output}"

    module = load_submission()
    calculated = module.get_julian_date(datetime.datetime(2024, 1, 1, 12, 0, 0))
    assert isinstance(calculated, (int, float)) and not isinstance(calculated, bool)
    assert math.isfinite(calculated)
    assert abs(float(output) - calculated) < 1e-9, "jd_output.txt was not produced by the corrected calculation"


def test_jd_py_fixed():
    jd_file = "/home/user/astro_calc/jd.py"
    assert os.path.isfile(jd_file), f"{jd_file} does not exist"

    with open(jd_file, "r") as f:
        content = f.read()

    assert "term3 = int((275 * M) / 9)" in content, "jd.py does not contain the corrected formula (division by 9)"
    assert "term3 = int((275 * M) / 8)" not in content, "jd.py still contains the buggy formula (division by 8)"


def test_julian_date_behavior_over_many_datetimes():
    module = load_submission()

    cases = [
        datetime.datetime(1901, 1, 1, 0, 0, 0),
        datetime.datetime(1904, 2, 29, 23, 59, 59),
        datetime.datetime(1970, 1, 1, 0, 0, 0),
        datetime.datetime(1999, 12, 31, 23, 59, 59),
        datetime.datetime(2000, 1, 1, 12, 0, 0),
        datetime.datetime(2000, 2, 29, 6, 30, 15),
        datetime.datetime(2024, 1, 1, 12, 0, 0),
        datetime.datetime(2099, 12, 31, 23, 59, 59),
    ]

    # Add verifier-selected dates so a fixed lookup or constant implementation cannot pass.
    rng = random.SystemRandom()
    start = datetime.datetime(1901, 1, 1)
    end = datetime.datetime(2100, 1, 1)
    span_seconds = int((end - start).total_seconds())
    for _ in range(200):
        cases.append(start + datetime.timedelta(seconds=rng.randrange(span_seconds)))

    for dt in cases:
        actual = module.get_julian_date(dt)
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), f"Non-numeric result for {dt!r}"
        assert math.isfinite(actual), f"Non-finite result for {dt!r}"
        expected = expected_julian_date(dt)
        assert abs(actual - expected) < 1e-7, f"Incorrect Julian Date for {dt!r}: expected {expected}, got {actual}"


def test_test_jd_passes():
    # Ensure that the test_jd.py test passes after the fix
    result = subprocess.run(
        ["python3", "test_jd.py"],
        cwd="/home/user/astro_calc",
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"test_jd.py failed to run successfully:\n{result.stderr}"
    assert "Tests passed" in result.stdout, "test_jd.py did not output 'Tests passed'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
