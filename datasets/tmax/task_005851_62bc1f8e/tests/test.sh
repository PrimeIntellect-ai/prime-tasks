#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import stat
import subprocess
import tempfile


def expected_output():
    t1 = 1622505600
    t2 = 1622511005
    hour1 = datetime.datetime.fromtimestamp(t1, datetime.timezone.utc).hour
    hour2 = datetime.datetime.fromtimestamp(t2, datetime.timezone.utc).hour
    diff_hours = (t2 - t1) / 3600.0
    return "\n".join([
        f"Local Hour 1: {hour1}",
        f"Local Hour 2: {hour2}",
        f"Exact Diff: {diff_hours:.4f}",
    ])


def test_solution_txt_content():
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), f"{solution_path} does not exist. Did you redirect the output?"

    with open(solution_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "Local Hour 1: 0",
        "Local Hour 2: 1",
        "Exact Diff: 1.5014"
    ]

    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {solution_path}."

    assert content == expected_output(), "solution.txt does not contain exactly the corrected program output."


def test_run_diag_sh_fixed():
    script_path = "/home/user/run_diag.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    # The script should now export TZ=UTC (quotes are optional but possible)
    assert re.search(r"TZ=['\"]?UTC['\"]?", content), "run_diag.sh does not correctly set TZ=UTC."
    assert "Mars/Phobos" not in content, "run_diag.sh still contains the incorrect Mars/Phobos timezone."


def test_calc_cpp_fixed():
    calc_path = "/home/user/calc.cpp"
    assert os.path.isfile(calc_path), f"{calc_path} does not exist."

    with open(calc_path, "r") as f:
        content = f.read()

    # The exact integer division bug should be gone
    bug_pattern = r"double\s+diff_hours\s*=\s*\(t2\s*-\s*t1\)\s*/\s*3600\s*;"
    assert not re.search(bug_pattern, content), "The integer division bug is still present in calc.cpp."


def test_compiled_source_behavior():
    with tempfile.TemporaryDirectory() as tmpdir:
        binary = os.path.join(tmpdir, "calc")
        compiled = subprocess.run(
            ["g++", "-std=c++17", "-o", binary, "/home/user/calc.cpp"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compiled.returncode == 0, f"calc.cpp failed to compile:\n{compiled.stderr}"

        env = os.environ.copy()
        env["TZ"] = "UTC"
        executed = subprocess.run(
            [binary],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert executed.returncode == 0, f"Compiled calc.cpp failed:\n{executed.stderr}"
        assert executed.stdout.strip() == expected_output(), "Compiled calc.cpp does not produce the corrected UTC result."


def test_diagnostic_script_behavior_and_saved_output():
    binary = "/home/user/calc"
    if os.path.lexists(binary):
        os.remove(binary)

    env = os.environ.copy()
    # A non-UTC inherited value ensures the script itself must correct TZ.
    env["TZ"] = "America/Los_Angeles"
    executed = subprocess.run(
        ["/home/user/run_diag.sh"],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert executed.returncode == 0, f"run_diag.sh failed:\n{executed.stderr}"
    assert os.path.isfile(binary), "run_diag.sh did not compile /home/user/calc."
    mode = os.stat(binary).st_mode
    assert stat.S_ISREG(mode) and os.access(binary, os.X_OK), "run_diag.sh did not create an executable calc binary."
    assert executed.stdout.strip() == expected_output(), "run_diag.sh does not produce the corrected output under a non-UTC inherited environment."

    with open("/home/user/solution.txt", "r") as f:
        saved = f.read().strip()
    assert saved == executed.stdout.strip(), "solution.txt is not the output produced by the corrected run_diag.sh."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
