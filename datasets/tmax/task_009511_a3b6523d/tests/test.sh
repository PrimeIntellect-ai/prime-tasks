#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
from decimal import Decimal, InvalidOperation, getcontext

import pytest

getcontext().prec = 80
CALLS = []


def derive_expected_rows():
    rows = []
    dt = Decimal("0.5")
    previous = None
    iteration = 1

    while True:
        t = Decimal(0)
        y = Decimal(1)
        while t < Decimal(1):
            y = y + y * dt
            t = t + dt

        rows.append((iteration, dt, y))
        if previous is not None and abs(y - previous) < Decimal("0.05"):
            return rows

        previous = y
        dt = dt / Decimal(2)
        iteration += 1
        assert iteration < 100, "Expected convergence was not reached."


EXPECTED_ROWS = derive_expected_rows()


def decimal_close(actual, expected, tolerance=Decimal("1e-12")):
    return abs(actual - expected) <= tolerance * max(Decimal(1), abs(expected))


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    global CALLS

    script = "/home/user/orchestrate.sh"
    assert os.path.isfile(script), f"Script {script} is missing."
    mode = os.stat(script).st_mode
    assert bool(mode & stat.S_IXUSR), f"Script {script} is not executable."

    for output in ("/home/user/results.csv", "/home/user/report.md"):
        if os.path.lexists(output):
            os.unlink(output)

    simulator = "/home/user/sim_euler.sh"
    assert os.path.isfile(simulator), f"Simulator {simulator} is missing."

    fd, backup = tempfile.mkstemp(prefix="sim_euler_original_", dir="/tmp")
    os.close(fd)
    os.unlink(backup)
    fd, call_log = tempfile.mkstemp(prefix="sim_euler_calls_", dir="/tmp")
    os.close(fd)

    os.replace(simulator, backup)
    wrapper = (
        "#!/bin/bash\n"
        + "printf '%s\\t%s\\n' \"$#\" \"$1\" >> " + shlex.quote(call_log) + "\n"
        + "exec " + shlex.quote(backup) + " \"$@\"\n"
    )
    with open(simulator, "w") as f:
        f.write(wrapper)
    os.chmod(simulator, 0o755)

    try:
        completed = subprocess.run(
            [script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        with open(call_log, "r") as f:
            CALLS = [line.rstrip("\n").split("\t", 1) for line in f if line.strip()]
    finally:
        if os.path.lexists(simulator):
            if os.path.isdir(simulator) and not os.path.islink(simulator):
                shutil.rmtree(simulator)
            else:
                os.unlink(simulator)
        os.replace(backup, simulator)
        if os.path.exists(call_log):
            os.unlink(call_log)

    assert completed.returncode == 0, (
        f"orchestrate.sh exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )


def test_orchestrate_script_exists_and_executable():
    file_path = "/home/user/orchestrate.sh"
    assert os.path.isfile(file_path), f"Script {file_path} is missing."
    st = os.stat(file_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {file_path} is not executable."


def test_simulator_was_called_for_each_refinement():
    assert len(CALLS) == len(EXPECTED_ROWS), (
        f"Expected {len(EXPECTED_ROWS)} simulator calls, found {len(CALLS)}."
    )
    for call, (_, expected_dt, _) in zip(CALLS, EXPECTED_ROWS):
        assert call[0] == "1", "sim_euler.sh must receive the current dt as its only argument."
        try:
            actual_dt = Decimal(call[1])
        except (InvalidOperation, IndexError):
            pytest.fail(f"Invalid dt passed to sim_euler.sh: {call}")
        assert actual_dt == expected_dt, (
            f"Expected simulator dt {expected_dt}, got {call[1]}."
        )


def test_results_csv_content():
    file_path = "/home/user/results.csv"
    assert os.path.isfile(file_path), f"Results file {file_path} is missing."

    with open(file_path, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, f"{file_path} is empty."
    assert rows[0] == ["iteration", "dt", "final_y"], f"{file_path} has incorrect header."
    assert len(rows) == 6, (
        f"{file_path} should have exactly 5 data rows (plus header), found {len(rows)-1}."
    )
    assert len(rows) == len(EXPECTED_ROWS) + 1

    for row, (expected_iteration, expected_dt, expected_y) in zip(rows[1:], EXPECTED_ROWS):
        assert len(row) == 3, f"CSV row must have exactly 3 fields: {row}"
        assert row[0] == str(expected_iteration), (
            f"Expected iteration {expected_iteration}, got {row[0]}."
        )
        try:
            actual_dt = Decimal(row[1])
            actual_y = Decimal(row[2])
        except InvalidOperation:
            pytest.fail(f"CSV row contains a non-numeric dt or final_y: {row}")
        assert actual_dt == expected_dt, f"Expected dt {expected_dt}, got {row[1]}."
        assert decimal_close(actual_y, expected_y), (
            f"Expected final_y approximately {expected_y}, got {row[2]}."
        )

    last_row = rows[-1]
    assert last_row[0] == "5", f"Expected final iteration to be 5, got {last_row[0]}."
    dt_val = float(last_row[1])
    assert math.isclose(dt_val, 0.03125, rel_tol=1e-5), (
        f"Expected final dt to be 0.03125, got {last_row[1]}."
    )
    y_val = float(last_row[2])
    expected_final_y = float(EXPECTED_ROWS[-1][2])
    assert math.isclose(y_val, expected_final_y, rel_tol=1e-5), (
        f"Expected final y to be approx {expected_final_y}, got {last_row[2]}."
    )


def test_report_md_content():
    file_path = "/home/user/report.md"
    assert os.path.isfile(file_path), f"Report file {file_path} is missing."

    with open(file_path, "r") as f:
        raw = f.read()

    assert raw.endswith("\n") or "\n" not in raw, "Report must contain exactly one line."
    content = raw[:-1] if raw.endswith("\n") else raw
    assert "\n" not in content, "Report must contain exactly one line."

    number = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)"
    pattern = re.compile(
        rf"Convergence achieved at iteration (\d+) with step size ({number}) "
        rf"and final value ({number})\."
    )
    match = pattern.fullmatch(content)
    assert match, f"Report content does not match expected format. Got: {content}"

    expected_iteration, expected_dt, expected_y = EXPECTED_ROWS[-1]
    assert int(match.group(1)) == expected_iteration
    assert Decimal(match.group(2)) == expected_dt
    assert decimal_close(Decimal(match.group(3)), expected_y)

    with open("/home/user/results.csv", "r", newline="") as f:
        final_csv_row = list(csv.reader(f))[-1]
    assert int(match.group(1)) == int(final_csv_row[0])
    assert Decimal(match.group(2)) == Decimal(final_csv_row[1])
    assert Decimal(match.group(3)) == Decimal(final_csv_row[2])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
