#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/run_tests.sh"
REPORT_PATH = "/home/user/stability_report.csv"
SOLVER_PATH = "/home/user/euler_ode.py"
BASELINE_PATH = "/home/user/baseline.txt"
DTS = ["0.2", "0.8", "1.2", "2.0"]


def run_script():
    return subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )


def expected_report(values, regression):
    lines = ["dt,final_value,status"]
    for dt in DTS:
        value = values[dt]
        status = "STABLE" if abs(Decimal(value)) < Decimal("10.0") else "UNSTABLE"
        lines.append(f"{dt},{value},{status}")
    lines.append(f"REGRESSION_CHECK:{regression}")
    return "\n".join(lines)


def assert_report(expected):
    assert os.path.isfile(REPORT_PATH), f"Expected report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        content = f.read()
    assert content.strip() == expected.strip(), (
        f"Content of {REPORT_PATH} does not match expected.\n"
        f"Expected:\n{expected.strip()}\n\nGot:\n{content.strip()}"
    )


def test_run_tests_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Expected script {SCRIPT_PATH} to be executable."


def test_stability_report_exists_and_content():
    result = run_script()
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    expected_content = (
        "dt,final_value,status\n"
        "0.2,0.000000,STABLE\n"
        "0.8,0.002177,STABLE\n"
        "1.2,14.757891,UNSTABLE\n"
        "2.0,-243.000000,UNSTABLE\n"
        "REGRESSION_CHECK:PASS\n"
    )
    assert_report(expected_content)


def test_script_actually_invokes_solver_and_computes_results():
    token = secrets.token_hex(4)
    values = {
        "0.2": f"-0.{token[:6]}",
        "0.8": f"10.{token[:6]}",
        "1.2": f"0.{token[2:8]}",
        "2.0": "-10.000000",
    }
    log_path = f"/tmp/euler_calls_{token}.log"

    with tempfile.TemporaryDirectory() as backup_dir:
        solver_backup = os.path.join(backup_dir, "euler_ode.py")
        shutil.copy2(SOLVER_PATH, solver_backup)
        with open(BASELINE_PATH, "rb") as f:
            baseline_backup = f.read()
        baseline_mode = stat.S_IMODE(os.stat(BASELINE_PATH).st_mode)

        wrapper = (
            "#!/usr/bin/env python3\n"
            "import json, sys\n"
            f"values = json.loads({json.dumps(json.dumps(values))})\n"
            f"log_path = {log_path!r}\n"
            "if len(sys.argv) != 2 or sys.argv[1] not in values:\n"
            "    raise SystemExit(2)\n"
            "with open(log_path, 'a') as f:\n"
            "    f.write(sys.argv[1] + '\\n')\n"
            "print(values[sys.argv[1]])\n"
        )

        try:
            with open(SOLVER_PATH, "w") as f:
                f.write(wrapper)
            os.chmod(SOLVER_PATH, 0o755)

            # Matching baseline must produce PASS.
            with open(BASELINE_PATH, "wb") as f:
                f.write(values["0.2"].encode())
            if os.path.exists(log_path):
                os.unlink(log_path)
            result = run_script()
            assert result.returncode == 0, (
                f"Instrumented execution failed.\nstdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            )
            assert_report(expected_report(values, "PASS"))
            assert os.path.isfile(log_path), "The submitted script did not invoke euler_ode.py."
            with open(log_path) as f:
                calls = f.read().splitlines()
            assert calls == DTS, f"Expected solver calls {DTS}, got {calls}."

            # A changed baseline must be compared against the captured dt=0.2 output.
            with open(BASELINE_PATH, "wb") as f:
                f.write((values["0.2"] + "-mismatch").encode())
            os.unlink(log_path)
            result = run_script()
            assert result.returncode == 0, (
                f"Instrumented mismatch execution failed.\nstdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            )
            assert_report(expected_report(values, "FAIL"))
            with open(log_path) as f:
                calls = f.read().splitlines()
            assert calls == DTS, f"Expected solver calls {DTS}, got {calls}."
        finally:
            shutil.copy2(solver_backup, SOLVER_PATH)
            with open(BASELINE_PATH, "wb") as f:
                f.write(baseline_backup)
            os.chmod(BASELINE_PATH, baseline_mode)
            if os.path.exists(log_path):
                os.unlink(log_path)
            # Restore the required final report using the real solver and baseline.
            run_script()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
