#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess

SIMULATOR = "/home/user/simulate_allele.sh"
OPTIMIZER = "/home/user/optimize_m.sh"
RESULT = "/home/user/result.txt"


def simulate(m, dt=0.01):
    w = 0.99
    b = 2.0
    for _ in range(1000):
        dw = -m * w + b * w * (1 - w)
        w = w + dw * dt
    return w


def simulate_while_loop(m, dt=0.01):
    w = 0.99
    b = 2.0
    t = 0.0
    while t < 10:
        dw = -m * w + b * w * (1 - w)
        w = w + dw * dt
        t += dt
    return w


def get_expected_result():
    for i in range(100, 251):
        m = i / 100.0
        w = simulate(m)
        if w < 0.1000:
            return m, w
    return None, None


def parse_result(path=RESULT):
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    match = re.search(r"m=([0-9.]+),\s*W=([0-9.]+)", content)
    assert match is not None, f"result.txt format is incorrect. Found: {content}"
    return float(match.group(1)), float(match.group(2)), content


def test_simulate_allele_modified():
    assert os.path.isfile(SIMULATOR), f"File {SIMULATOR} does not exist."
    with open(SIMULATOR, "r") as f:
        content = f.read()
    assert "dt=0.01" in content, "simulate_allele.sh does not have dt=0.01 as default."
    assert "dt=0.5" not in content, "simulate_allele.sh still contains the old dt=0.5."

    # Execute both the default-dt path and explicit-dt path and compare them
    # with independently calculated explicit-Euler values.
    for m in (1.00, 1.73, 2.50):
        default_output = subprocess.check_output(
            [SIMULATOR, f"{m:.2f}"], text=True, timeout=10
        ).strip()
        explicit_output = subprocess.check_output(
            [SIMULATOR, f"{m:.2f}", "0.01"], text=True, timeout=10
        ).strip()
        try:
            default_w = float(default_output)
            explicit_w = float(explicit_output)
        except ValueError:
            raise AssertionError(
                f"Simulator did not emit a numeric allele fraction: {default_output!r}, {explicit_output!r}"
            )
        expected = simulate_while_loop(m, 0.01)
        assert abs(default_w - expected) < 1e-6, (
            f"Default simulation is incorrect for m={m:.2f}: got {default_w}, expected {expected}"
        )
        assert abs(explicit_w - expected) < 1e-6, (
            f"Explicit-dt simulation is incorrect for m={m:.2f}: got {explicit_w}, expected {expected}"
        )


def test_optimize_m_script_exists_and_runs_grid_search():
    assert os.path.isfile(OPTIMIZER), f"File {OPTIMIZER} does not exist."
    assert os.access(OPTIMIZER, os.X_OK), f"File {OPTIMIZER} is not executable."

    # Replace the simulator temporarily with an unpredictable test double. This
    # verifies that the optimizer really searches the requested grid, supplies
    # dt=0.01, and records the first qualifying simulator output rather than a
    # precomputed answer.
    backup = "/tmp/simulate_allele.original"
    calls = "/tmp/optimize_grid_calls"
    cutoff = 125 + secrets.randbelow(101)  # 1.25 through 2.25
    shutil.copy2(SIMULATOR, backup)
    if os.path.exists(calls):
        os.unlink(calls)
    if os.path.exists(RESULT):
        os.unlink(RESULT)

    mock = f'''#!/bin/bash
printf '%s %s\\n' "$1" "$2" >> {calls}
i=$(awk -v m="$1" 'BEGIN {{ printf "%d", m * 100 + 0.5 }}')
if [ "$i" -lt {cutoff} ]; then
    printf '0.200000\\n'
elif [ "$i" -eq {cutoff} ]; then
    printf '0.050000\\n'
else
    printf '0.040000\\n'
fi
'''

    try:
        with open(SIMULATOR, "w") as f:
            f.write(mock)
        os.chmod(SIMULATOR, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                            stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        subprocess.run([OPTIMIZER], cwd="/home/user", check=True, timeout=30)

        assert os.path.isfile(calls), "Optimizer never called ./simulate_allele.sh."
        with open(calls, "r") as f:
            invocation_lines = [line.strip().split() for line in f if line.strip()]

        assert len(invocation_lines) == 151, (
            f"Expected one simulator call for each of 151 grid values, got {len(invocation_lines)}."
        )
        for offset, fields in enumerate(invocation_lines):
            assert len(fields) == 2, f"Malformed simulator invocation: {fields}"
            expected_i = 100 + offset
            try:
                actual_i = round(float(fields[0]) * 100)
                actual_dt = float(fields[1])
            except ValueError:
                raise AssertionError(f"Non-numeric simulator arguments: {fields}")
            assert actual_i == expected_i, (
                f"Grid call {offset + 1} used m={fields[0]}, expected {expected_i / 100:.2f}."
            )
            assert abs(actual_dt - 0.01) < 1e-12, (
                f"Simulator call for m={fields[0]} used dt={fields[1]} instead of 0.01."
            )

        actual_m, actual_w, _ = parse_result()
        assert abs(actual_m - cutoff / 100.0) < 1e-9, (
            f"Optimizer did not select the smallest qualifying mocked m; got {actual_m}."
        )
        assert abs(actual_w - 0.05) < 1e-9, (
            f"Optimizer did not save the corresponding mocked simulator output; got {actual_w}."
        )
    finally:
        os.replace(backup, SIMULATOR)

    # Execute the optimizer against the submitted real simulator as well.
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    subprocess.run([OPTIMIZER], cwd="/home/user", check=True, timeout=60)


def test_result_file():
    actual_m, actual_w, content = parse_result()
    expected_m, expected_w = get_expected_result()
    assert expected_m is not None, "Could not compute expected result."
    assert abs(actual_m - expected_m) < 1e-5, f"Expected m={expected_m:.2f}, got {actual_m}"
    assert abs(actual_w - expected_w) < 1e-4, f"Expected W={expected_w:.6f}, got {actual_w}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
