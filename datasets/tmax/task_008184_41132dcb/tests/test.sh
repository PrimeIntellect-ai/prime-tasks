#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/fit_model.c"
BINARY = f"{HOME}/fit_model"
DATA = f"{HOME}/data.csv"
OUTPUT = f"{HOME}/optimal_k.txt"
PLOT_SCRIPT = f"{HOME}/plot.gp"
PLOT_IMAGE = f"{HOME}/plot.png"
REBUILT = "/tmp/fit_model_rebuilt"


def run_program(path):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [path], cwd=HOME,
        env={**os.environ, "OMP_NUM_THREADS": "2"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{path} did not create {OUTPUT}."
    with open(OUTPUT, "r") as f:
        text = f.read().strip()
    try:
        value = float(text)
    except ValueError:
        pytest.fail(f"Could not parse {text!r} as a float in {OUTPUT}.")
    assert math.isfinite(value), f"Program produced a non-finite k value: {value}."
    return value


def expected_k(rows):
    def simulate(k, t_end):
        y = 5.0
        t = 0.0
        dt = 0.01
        while t < t_end:
            if t + dt > t_end:
                dt = t_end - t
            y = y - k * y * dt
            t += dt
            dt = 0.01
        return y

    def mse(k):
        error = 0.0
        for t, y in rows:
            diff = simulate(k, t) - y
            error += diff * diff
        return error / len(rows)

    k = 2.1
    for _ in range(100):
        grad = (mse(k + 0.001) - mse(k - 0.001)) / 0.002
        k -= 0.01 * grad
    return float(f"{k:.4f}")


def write_rows(rows):
    with open(DATA, "w") as f:
        for t, y in rows:
            f.write(f"{t:.10f},{y:.10f}\n")


def test_fit_model_c_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "0.01" in content, "The step size dt was not changed to 0.01 in fit_model.c."
    matches = re.findall(r'dt\s*=\s*1\.0\s*;', content)
    assert len(matches) == 0, "The incorrect step size dt = 1.0 is still present in fit_model.c."

    # The initialization and reset must both use the requested value.
    correct_assignments = re.findall(r'dt\s*=\s*0\.01\s*;', content)
    assert len(correct_assignments) >= 2, (
        "simulate must initialize dt to 0.01 and reset it to 0.01 inside the loop."
    )

    compile_result = subprocess.run(
        ["gcc", "-O2", "-fopenmp", SOURCE, "-lm", "-o", REBUILT],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        "fit_model.c does not compile with OpenMP and the math library: "
        + compile_result.stderr
    )


def test_fit_model_compiled():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary."


def test_compiled_binary_runs_on_original_data():
    value = run_program(BINARY)
    assert abs(value - 0.5255) < 0.01, (
        f"Expected optimal k to be around 0.5255, but got {value}."
    )


def test_binary_performs_the_model_optimization():
    original_data = open(DATA, "rb").read()
    original_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None
    try:
        for _ in range(2):
            rate = 0.32 + secrets.randbelow(4400) / 10000.0
            rows = []
            for i in range(10):
                noise = (secrets.randbelow(2001) - 1000) / 1000000.0
                rows.append((float(i), 5.0 * math.exp(-rate * i) + noise))
            write_rows(rows)

            expected = expected_k(rows)
            submitted = run_program(BINARY)
            rebuilt = run_program(REBUILT)
            assert abs(submitted - expected) <= 0.00011, (
                f"Submitted binary produced {submitted}; independently derived result is {expected}."
            )
            assert abs(rebuilt - expected) <= 0.00011, (
                f"Program compiled from fit_model.c produced {rebuilt}; expected {expected}."
            )
            assert abs(submitted - rebuilt) <= 0.00011, (
                "Submitted binary does not behave like the program compiled from fit_model.c."
            )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        if original_output is not None:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT):
            os.remove(OUTPUT)


def test_optimal_k_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    try:
        k_val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse {content} as a float in {OUTPUT}.")
    assert abs(k_val - 0.5255) < 0.01, (
        f"Expected optimal k to be around 0.5255, but got {k_val}."
    )


def test_plot_gp():
    assert os.path.isfile(PLOT_SCRIPT), f"Gnuplot script {PLOT_SCRIPT} is missing."
    with open(PLOT_SCRIPT, "r") as f:
        content = f.read().lower()

    # Preserve the original script assertions.
    assert "set terminal png" in content or "set term png" in content, (
        "The gnuplot script does not set the terminal to png."
    )
    assert "set output" in content and "plot.png" in content, (
        "The gnuplot script does not set the output to plot.png."
    )
    assert "plot" in content and "data.csv" in content, (
        "The gnuplot script does not plot the data.csv file."
    )

    assert re.search(r"set\s+datafile\s+separator\s+(['\"]),\1", content), (
        "The gnuplot script must configure comma-separated CSV input."
    )
    assert re.search(r"using\s+1\s*:\s*2", content), (
        "The plot must use column 1 for Time and column 2 for Value."
    )
    assert re.search(r"(?:with|w)\s+points\b", content), (
        "The experimental data must be plotted using points."
    )

    if os.path.exists(PLOT_IMAGE):
        os.remove(PLOT_IMAGE)
    result = subprocess.run(
        ["gnuplot", PLOT_SCRIPT], cwd=HOME,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, "Invalid gnuplot script: " + result.stderr
    assert os.path.isfile(PLOT_IMAGE), f"The script did not generate {PLOT_IMAGE}."
    with open(PLOT_IMAGE, "rb") as f:
        signature = f.read(8)
    assert signature == b"\x89PNG\r\n\x1a\n", "plot.png is not a valid PNG file."
    assert os.path.getsize(PLOT_IMAGE) > 100, "Generated plot.png is unexpectedly empty."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
