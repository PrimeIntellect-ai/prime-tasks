#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shutil
import subprocess
import tempfile

SOURCE_PATH = "/home/user/density.c"
LOG_PATH = "/home/user/validation.log"


def test_01_source_compiles_runs_and_implements_trapezoidal_work():
    assert os.path.isfile(SOURCE_PATH), f"File {SOURCE_PATH} does not exist"
    assert not os.path.islink(SOURCE_PATH), f"File {SOURCE_PATH} must be a regular source file"

    with open(SOURCE_PATH, "r", encoding="utf-8", errors="strict") as f:
        source = f.read()

    # Ignore comments when checking that the requested algorithm is represented in code.
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(r"\b10000000\b", code), "density.c does not use N=10,000,000"
    assert re.search(r"\b(for|while)\s*\(", code), "density.c does not contain the required numerical loop"
    assert re.search(r"(?:0?\.5(?:0*)?\b|/\s*2(?:\.0*)?\b)", code), (
        "density.c does not show trapezoidal endpoint/pair weighting"
    )
    assert "atan" in code, "density.c does not calculate the analytical antiderivative"
    assert "validation.log" in source, "density.c does not write validation.log"

    build_dir = tempfile.mkdtemp(prefix="density_verify_")
    try:
        copied_source = os.path.join(build_dir, "density.c")
        shutil.copyfile(SOURCE_PATH, copied_source)

        compile_obj = subprocess.run(
            ["gcc", "-std=c11", "-O0", "--coverage", "-c", "density.c", "-o", "density.o"],
            cwd=build_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert compile_obj.returncode == 0, f"density.c failed to compile:\n{compile_obj.stderr}"

        link = subprocess.run(
            ["gcc", "--coverage", "density.o", "-lm", "-o", "density"],
            cwd=build_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert link.returncode == 0, f"density.c failed to link:\n{link.stderr}"

        # The checked log must be freshly produced by the submitted C program.
        if os.path.lexists(LOG_PATH):
            os.remove(LOG_PATH)
        run = subprocess.run(
            [os.path.join(build_dir, "density")],
            cwd="/home/user", text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=60
        )
        assert run.returncode == 0, f"Compiled density program failed:\n{run.stderr}"
        assert os.path.isfile(LOG_PATH), "Running the compiled density.c did not create validation.log"

        # Coverage confirms that the submitted executable actually performed a loop at
        # the requested scale rather than only printing precomputed values.
        gcov = subprocess.run(
            ["gcov", "density.c"], cwd=build_dir, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert gcov.returncode == 0, f"Could not inspect execution coverage:\n{gcov.stderr}"
        gcov_path = os.path.join(build_dir, "density.c.gcov")
        assert os.path.isfile(gcov_path), "Coverage report for density.c was not generated"

        hot_lines = []
        max_count = 0
        with open(gcov_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                match = re.match(r"\s*([0-9]+)(?:\*)?:\s*\d+:(.*)$", line)
                if match:
                    count = int(match.group(1))
                    max_count = max(max_count, count)
                    if count >= 9_999_999:
                        hot_lines.append(match.group(2))

        assert max_count >= 9_999_999, (
            "The compiled program did not execute numerical work at the N=10,000,000 scale"
        )
        assert any("/" in line and ("x" in line or "alpha" in line) for line in hot_lines), (
            "The high-iteration work did not evaluate the requested density function"
        )
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_02_validation_log_exists_and_format():
    """Test that the freshly generated validation.log has the correct format and values."""
    assert os.path.isfile(LOG_PATH), f"File {LOG_PATH} does not exist. Did you run your C program?"

    with open(LOG_PATH, "r") as f:
        text = f.read()

    ana_match = re.search(r'Analytical:\s*([0-9.]+)', text)
    num_match = re.search(r'Numerical:\s*([0-9.]+)', text)
    err_match = re.search(r'Error:\s*([0-9.]+)', text)

    assert ana_match is not None, "Could not find 'Analytical: <value>' in validation.log"
    assert num_match is not None, "Could not find 'Numerical: <value>' in validation.log"
    assert err_match is not None, "Could not find 'Error: <value>' in validation.log"

    # Enforce precisely three lines and six digits after each decimal point.
    exact = re.fullmatch(
        r"Analytical: ([0-9]+\.[0-9]{6})\n"
        r"Numerical: ([0-9]+\.[0-9]{6})\n"
        r"Error: ([0-9]+\.[0-9]{6})\n?",
        text,
    )
    assert exact is not None, "validation.log is not in the precise required three-line format"

    ana_val = float(ana_match.group(1))
    num_val = float(num_match.group(1))
    err_val = float(err_match.group(1))

    alpha = 0.001
    expected_ana = (2.0 / alpha) * math.atan(1.0 / alpha)

    assert abs(ana_val - expected_ana) < 0.001, f"Analytical value {ana_val} is incorrect. Expected ~{expected_ana:.6f}"
    assert abs(num_val - expected_ana) < 0.01, f"Numerical value {num_val} is too far from analytical value."
    assert err_val < 0.01, f"Reported error {err_val} is too high."

    expected_err = abs(ana_val - num_val)
    assert abs(err_val - expected_err) < 0.001, f"Reported error {err_val} does not match actual difference {expected_err:.6f}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
