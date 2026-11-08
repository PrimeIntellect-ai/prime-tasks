#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import math
import os
import re
import subprocess
import sys
import tarfile
import tempfile

PROJECT = "/home/user/mathtool"
BINARY = os.path.join(PROJECT, "mathtool")
REPORT = os.path.join(PROJECT, "test_report.json")
EXPECTED_CASES = [
    {"expression": "3 + 5 * 2", "expected": 13.0},
    {"expression": "pow(2, 3) - 1", "expected": 7.0},
    {"expression": "10.0005 + 0.0005", "expected": 10.001},
]


def read_report():
    assert os.path.isfile(REPORT), f"{REPORT} is missing."
    with open(REPORT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"{REPORT} is not valid JSON."


def test_makefile_fixed_and_binary_compiled():
    makefile_path = os.path.join(PROJECT, "Makefile")
    assert os.path.isfile(makefile_path), f"{makefile_path} is missing."
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-lm" in content, "Makefile does not link the math library (-lm)."

    # Rebuild from the submitted project so a planted executable cannot satisfy
    # the binary checks without the build itself succeeding.
    subprocess.run(["make", "clean"], cwd=PROJECT, check=True, timeout=30)
    subprocess.run(["make"], cwd=PROJECT, check=True, timeout=30)

    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."

    ldd_output = subprocess.check_output(["ldd", BINARY], text=True)
    assert "libm.so" in ldd_output, "mathtool binary is not linked to libm."

    # Exercise the real rebuilt binary and check its numerical results rather
    # than trusting test_report.json.
    for case in EXPECTED_CASES:
        proc = subprocess.run(
            [BINARY, case["expression"]],
            text=True,
            capture_output=True,
            timeout=5,
        )
        assert proc.returncode == 0, (
            f"mathtool failed for {case['expression']!r}: {proc.stderr}"
        )
        try:
            actual = float(proc.stdout.strip())
        except ValueError:
            assert False, f"mathtool produced non-numeric output: {proc.stdout!r}"
        assert math.isfinite(actual), "mathtool output must be finite."
        assert abs(actual - case["expected"]) <= 0.0001, (
            f"Wrong result for {case['expression']!r}: {actual}"
        )


def test_parser_c_fixed():
    parser_path = os.path.join(PROJECT, "src/parser.c")
    assert os.path.isfile(parser_path), f"{parser_path} is missing."
    with open(parser_path, "r") as f:
        content = f.read()

    assert re.search(r"malloc\s*\(\s*len\s*\+\s*1\s*\)", content), \
        "parser.c does not allocate len + 1 bytes."
    assert re.search(r"buf\s*\[\s*len\s*\]\s*=\s*['\"]\\[0o]0?['\"]", content), \
        "parser.c does not null-terminate the buffer."


def test_fixture_json():
    fixture_path = os.path.join(PROJECT, "tests/fixture.json")
    assert os.path.isfile(fixture_path), f"{fixture_path} is missing."
    with open(fixture_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{fixture_path} is not valid JSON."

    assert isinstance(data, list), "Fixture should be a JSON array."
    assert len(data) == 3, "Fixture should contain exactly 3 test cases."
    for case in EXPECTED_CASES:
        assert case in data, f"Missing expected test case in fixture: {case}"


def test_completed_test_runner_executes_binary_and_compares_results():
    runner = os.path.join(PROJECT, "tests/test_runner.py")
    assert os.path.isfile(runner), f"{runner} is missing."

    # Temporarily put an instrumented executable at ../mathtool. One run emits
    # a value outside tolerance and must report a failure; the final run emits
    # values within tolerance and must recreate the required passing report.
    fd, backup = tempfile.mkstemp(prefix=".mathtool-verifier-", dir=PROJECT)
    os.close(fd)
    os.unlink(backup)
    log_fd, log_path = tempfile.mkstemp(prefix="mathtool-calls-", suffix=".jsonl")
    os.close(log_fd)
    os.replace(BINARY, backup)

    wrapper = f'''#!/usr/bin/env python3
import json
import os
import sys
with open({log_path!r}, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
values = {{
    "3 + 5 * 2": 13.0,
    "pow(2, 3) - 1": 7.0,
    "10.0005 + 0.0005": 10.001,
}}
if len(sys.argv) != 2 or sys.argv[1] not in values:
    sys.exit(2)
expr = sys.argv[1]
delta = 0.001 if os.environ.get("VERIFIER_BAD") == "1" and expr == "pow(2, 3) - 1" else 0.00005
print(values[expr] + delta)
'''

    expected_calls = [[case["expression"]] for case in EXPECTED_CASES]

    def run_runner(bad):
        if os.path.exists(REPORT):
            os.unlink(REPORT)
        with open(log_path, "w"):
            pass
        env = os.environ.copy()
        env["VERIFIER_BAD"] = "1" if bad else "0"
        proc = subprocess.run(
            [sys.executable, runner],
            cwd=os.path.join(PROJECT, "tests"),
            env=env,
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert proc.returncode == 0, (
            f"test_runner.py failed: stdout={proc.stdout!r}, stderr={proc.stderr!r}"
        )
        with open(log_path, "r") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert calls == expected_calls, (
            "test_runner.py must invoke ../mathtool once for each fixture expression; "
            f"observed calls: {calls}"
        )
        return read_report()

    try:
        with open(BINARY, "w") as f:
            f.write(wrapper)
        os.chmod(BINARY, 0o755)

        bad_report = run_runner(True)
        assert bad_report.get("total") == 3, "Runner reported wrong total."
        assert bad_report.get("passed") == 2, \
            "Runner did not detect an output outside the tolerance."
        assert bad_report.get("failed") == 1, \
            "Runner did not record the failing numerical result."

        good_report = run_runner(False)
        assert good_report.get("total") == 3, "Runner reported wrong total."
        assert good_report.get("passed") == 3, \
            "Runner rejected outputs within the required tolerance."
        assert good_report.get("failed") == 0, "Runner reported unexpected failures."
    finally:
        if os.path.lexists(BINARY):
            os.unlink(BINARY)
        os.replace(backup, BINARY)
        if os.path.exists(log_path):
            os.unlink(log_path)


def test_test_report_json():
    data = read_report()
    assert data.get("total") == 3, "Test report 'total' should be 3."
    assert data.get("passed") == 3, "Test report 'passed' should be 3."
    assert data.get("failed") == 0, "Test report 'failed' should be 0."


def test_artifact_packaging():
    tar_path = "/home/user/artifact.tar.gz"
    assert os.path.isfile(tar_path), f"{tar_path} is missing."
    assert tarfile.is_tarfile(tar_path), f"{tar_path} is not a valid tar archive."

    with tarfile.open(tar_path, "r:gz") as tar:
        members = tar.getmembers()
        names = [member.name for member in members]

        assert len(names) == 2, f"Archive should contain exactly 2 files, found: {names}"
        assert "mathtool" in names, "Archive is missing 'mathtool'."
        assert "test_report.json" in names, "Archive is missing 'test_report.json'."
        assert all(member.isfile() for member in members), \
            "Both archive members must be regular files."

        archived_binary = tar.extractfile(tar.getmember("mathtool")).read()
        archived_report = tar.extractfile(tar.getmember("test_report.json")).read()
        assert tar.getmember("mathtool").mode & 0o111, \
            "Archived mathtool is not executable."

    with open(BINARY, "rb") as f:
        project_binary = f.read()
    with open(REPORT, "rb") as f:
        project_report = f.read()

    assert archived_binary == project_binary, \
        "Archived mathtool does not match the rebuilt project binary."
    assert archived_report == project_report, \
        "Archived test_report.json does not match the generated project report."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
