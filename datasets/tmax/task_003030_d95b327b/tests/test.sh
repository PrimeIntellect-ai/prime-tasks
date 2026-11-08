#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

SCRIPT = "/home/user/bootstrap_ci.sh"
CI_OUTPUT = "/home/user/ci_output.txt"
CONVERGENCE_OUTPUT = "/home/user/convergence.txt"


def clean_outputs():
    for path in (CI_OUTPUT, CONVERGENCE_OUTPUT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_script(input_path, iterations):
    clean_outputs()
    result = subprocess.run(
        ["bash", SCRIPT, input_path, str(iterations)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Script failed for {input_path} with {iterations} iterations. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(CI_OUTPUT), "Script did not create ci_output.txt."
    assert os.path.isfile(CONVERGENCE_OUTPUT), "Script did not create convergence.txt."


def read_ci_strict():
    with open(CI_OUTPUT, "r") as f:
        content = f.read().strip()
    match = re.fullmatch(r"Lower: ([+-]?(?:\d+)\.\d{3}), Upper: ([+-]?(?:\d+)\.\d{3}", content)
    assert match is not None, (
        "CI output must use the exact format 'Lower: X.XXX, Upper: Y.YYY'; "
        f"got {content!r}"
    )
    return float(match.group(1)), float(match.group(2))


def read_convergence(expected_iterations):
    with open(CONVERGENCE_OUTPUT, "r") as f:
        lines = f.read().strip().splitlines()
    expected_points = list(range(100, expected_iterations + 1, 100))
    assert len(lines) == len(expected_points), (
        f"Expected {len(expected_points)} convergence lines, got {len(lines)}."
    )
    values = []
    for line, point in zip(lines, expected_points):
        match = re.fullmatch(rf"Iteration {point}:\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)", line)
        assert match is not None, f"Invalid convergence line for iteration {point}: {line!r}"
        values.append(float(match.group(1)))
    return values


def test_script_exists():
    script_path = "/home/user/bootstrap_ci.sh"
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    # Check if it's a bash/shell script and not python/R/perl
    with open(script_path, 'r') as f:
        content = f.read().lower()
        assert "python" not in content[:100], "Script appears to be a Python script, but must be Bash/CLI."
        assert "perl" not in content[:100], "Script appears to be a Perl script, but must be Bash/CLI."
        assert " rscript" not in content[:100], "Script appears to be an R script, but must be Bash/CLI."


def test_script_behavior_and_prepare_required_run():
    # A randomly selected constant input makes every bootstrap mean known exactly.
    # The NaN lines verify filtering, while 200 verifies argument-driven loop and
    # convergence checkpoint handling.
    constant = secrets.randbelow(40) + 1.125
    fd, constant_path = tempfile.mkstemp(prefix="bootstrap_constant_", text=True)
    with os.fdopen(fd, "w") as f:
        f.write(f"{constant}\nNaN\n{constant}\nNaN\n{constant}\n")

    try:
        run_script(constant_path, 200)
        lower, upper = read_ci_strict()
        assert lower == pytest.approx(constant, abs=0.0005)
        assert upper == pytest.approx(constant, abs=0.0005)
        convergence = read_convergence(200)
        assert all(v == pytest.approx(constant, abs=1e-6) for v in convergence), (
            "Cumulative convergence averages are incorrect for constant data."
        )
    finally:
        os.remove(constant_path)

    # For four low observations and one observation 10 units higher, a size-five
    # replacement sample has mean low+2K where K~Binomial(5, 0.2). With 1000
    # replicates its 2.5th and 97.5th percentiles are overwhelmingly low and
    # low+6. This distinguishes replacement bootstrap percentiles from the input
    # mean, min/max, and sampling without replacement.
    low = float(secrets.randbelow(20) + 2)
    high = low + 10.0
    fd, skew_path = tempfile.mkstemp(prefix="bootstrap_skew_", text=True)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join([str(low)] * 4 + ["NaN", str(high)]) + "\n")

    try:
        run_script(skew_path, 1000)
        lower, upper = read_ci_strict()
        assert lower == pytest.approx(low, abs=0.0005), (
            f"Incorrect 2.5th bootstrap percentile: expected {low:.3f}, got {lower:.3f}."
        )
        assert upper == pytest.approx(low + 6.0, abs=0.0005), (
            f"Incorrect 97.5th bootstrap percentile: expected {low + 6.0:.3f}, got {upper:.3f}."
        )
        convergence = read_convergence(1000)
        assert all(low <= v <= high for v in convergence)
        assert convergence[-1] == pytest.approx(low + 2.0, abs=0.35), (
            "Final cumulative bootstrap average is inconsistent with the input mean."
        )
    finally:
        os.remove(skew_path)

    # Execute the exact required command last so the original final-state
    # assertions below inspect outputs genuinely produced from the provided data.
    run_script("/home/user/mutation_rates.txt", 1000)


def test_ci_output_format_and_values():
    output_path = "/home/user/ci_output.txt"
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    with open(output_path, 'r') as f:
        content = f.read().strip()

    match = re.match(r"^Lower:\s*([0-9.]+),\s*Upper:\s*([0-9.]+)$", content)
    assert match is not None, f"Format of {output_path} is incorrect. Expected 'Lower: X.XXX, Upper: Y.YYY', got '{content}'"

    lower_val = float(match.group(1))
    upper_val = float(match.group(2))

    assert 0.930 <= lower_val <= 1.010, f"Lower bound {lower_val} is out of expected statistical range [0.930, 1.010]."
    assert 1.060 <= upper_val <= 1.140, f"Upper bound {upper_val} is out of expected statistical range [1.060, 1.140]."


def test_convergence_output():
    output_path = "/home/user/convergence.txt"
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    with open(output_path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 10, f"Expected 10 lines in {output_path}, got {len(lines)}."

    for i, line in enumerate(lines):
        expected_iter = (i + 1) * 100
        match = re.match(rf"^Iteration {expected_iter}:\s*([0-9.]+)$", line)
        assert match is not None, f"Line {i+1} format is incorrect. Expected 'Iteration {expected_iter}: <value>', got '{line}'"

        val = float(match.group(1))
        assert 0.900 <= val <= 1.200, f"Cumulative average {val} at iteration {expected_iter} is out of expected range."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
