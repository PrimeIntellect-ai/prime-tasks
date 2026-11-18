#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess

INTEGRATE = "/home/user/sim/integrate.sh"
VALIDATE = "/home/user/sim/validate.sh"
RMSE_LOG = "/home/user/sim/rmse.log"
STATUS_LOG = "/home/user/sim/status.log"


def run_integrator(t_end):
    result = subprocess.run(
        [INTEGRATE, str(t_end)],
        cwd="/home/user/sim",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"{INTEGRATE} failed: {result.stderr}"

    points = []
    for line_number, line in enumerate(result.stdout.splitlines(), 1):
        fields = line.split()
        assert len(fields) == 2, f"Malformed integrator output on line {line_number}: {line!r}"
        try:
            t, y = map(float, fields)
        except ValueError:
            raise AssertionError(f"Non-numeric integrator output on line {line_number}: {line!r}")
        assert math.isfinite(t) and math.isfinite(y), f"Non-finite integrator output: {line!r}"
        points.append((t, y))

    assert len(points) >= 10, "Integrator emitted too few points to represent an adaptive integration."
    assert abs(points[0][0]) < 1e-12, "Integrator does not start at t=0."
    assert abs(points[0][1] - 1.0) < 1e-12, "Integrator does not start at y=1."
    assert all(points[i][0] > points[i - 1][0] for i in range(1, len(points))), \
        "Integrator time values are not strictly increasing."
    assert points[-1][0] >= t_end, f"Integrator stopped before t={t_end}."
    assert points[-1][0] <= t_end + 0.5 + 1e-9, "Integrator overshot the requested end time excessively."

    rmse = math.sqrt(sum((y - math.exp(-2.0 * t)) ** 2 for t, y in points) / len(points))
    return points, rmse


def run_validator():
    result = subprocess.run(
        [VALIDATE],
        cwd="/home/user/sim",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"{VALIDATE} failed to execute properly. Error: {result.stderr}"
    assert os.path.isfile(RMSE_LOG), f"{RMSE_LOG} was not created."
    assert os.path.isfile(STATUS_LOG), f"{STATUS_LOG} was not created."
    with open(RMSE_LOG) as f:
        rmse_content = f.read().strip()
    with open(STATUS_LOG) as f:
        status_content = f.read().strip()
    return rmse_content, status_content


def test_integrate_script_fixed():
    assert os.path.isfile(INTEGRATE), f"{INTEGRATE} does not exist."
    st = os.stat(INTEGRATE)
    assert bool(st.st_mode & stat.S_IXUSR), f"{INTEGRATE} is not executable."

    with open(INTEGRATE) as f:
        content = f.read()
    assert "dt_new = dt * (err / tol)" not in content, \
        "The bug in step-size adaptation logic was not fixed."

    # Exercise the repaired artifact and independently derive its accuracy.
    _, rmse_short = run_integrator(0.75)
    _, rmse_full = run_integrator(2.0)
    assert rmse_short < 0.05, f"Integrator RMSE at t=0.75 is {rmse_short}, not below 0.05."
    assert rmse_full < 0.05, f"Integrator RMSE at t=2.0 is {rmse_full}, not below 0.05."


def test_validate_script_exists_and_executable():
    assert os.path.isfile(VALIDATE), f"{VALIDATE} does not exist."
    st = os.stat(VALIDATE)
    assert bool(st.st_mode & stat.S_IXUSR), f"{VALIDATE} is not executable."


def test_validate_script_execution_and_output():
    # Compute the expected result directly from a fresh execution of integrate.sh.
    _, actual_rmse = run_integrator(2.0)
    rmse_content, status_content = run_validator()

    assert re.match(r"^RMSE: 0\.[0-9]{4}$", rmse_content), \
        f"RMSE log format is incorrect. Found: {rmse_content}"
    rmse_val = float(rmse_content.split(":")[1].strip())
    assert rmse_val < 0.05, \
        f"RMSE value {rmse_val} is not strictly less than 0.05. The integration fix might be incorrect."
    assert status_content == "PASS", f"Status log does not contain 'PASS'. Found: {status_content}"
    assert rmse_content == f"RMSE: {actual_rmse:.4f}", \
        f"validate.sh reported {rmse_content}, but independently computed RMSE is {actual_rmse:.4f}."

    # Ensure validate.sh really computes the statistic and FAIL branch rather than
    # merely writing a fixed successful result. Restore the submitted integrator afterward.
    with open(INTEGRATE, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(INTEGRATE).st_mode)
    fixture = b"#!/bin/bash\nprintf '0 1\\n0.5 0.9\\n1.0 0.8\\n2.0 0.7\\n'\n"
    fixture_points = [(0.0, 1.0), (0.5, 0.9), (1.0, 0.8), (2.0, 0.7)]
    fixture_rmse = math.sqrt(sum((y - math.exp(-2.0 * t)) ** 2 for t, y in fixture_points) / len(fixture_points))

    try:
        with open(INTEGRATE, "wb") as f:
            f.write(fixture)
        os.chmod(INTEGRATE, 0o755)
        fixture_rmse_content, fixture_status = run_validator()
        assert fixture_rmse_content == f"RMSE: {fixture_rmse:.4f}", \
            "validate.sh did not compute RMSE from integrate.sh output."
        assert fixture_status == "FAIL", \
            "validate.sh did not write FAIL for independently verified RMSE above 0.05."
    finally:
        with open(INTEGRATE, "wb") as f:
            f.write(original)
        os.chmod(INTEGRATE, original_mode)

    # Leave logs in the required final successful state and verify them again.
    final_rmse_content, final_status = run_validator()
    assert final_rmse_content == f"RMSE: {actual_rmse:.4f}"
    assert final_status == "PASS"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
