#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import re
import subprocess
import tempfile

import pytest

MODEL = "/home/user/model_fit.c"
PIPELINE = "/home/user/pipeline.sh"
OBSERVATIONS = "/home/user/observations.csv"
OUTPUT = "/home/user/refined_cells.txt"


def run(cmd, cwd="/home/user", timeout=15):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, timeout=timeout)


def parse_points(data):
    reader = csv.DictReader(io.StringIO(data))
    return [(float(row["x"]), float(row["y"]), float(row["v"])) for row in reader]


def expected_output(data, n, threshold):
    points = parse_points(data)
    lines = []

    def variance(cell_points):
        if not cell_points:
            return 0.0
        mean = sum(p[2] for p in cell_points) / len(cell_points)
        return sum((p[2] - mean) ** 2 for p in cell_points) / len(cell_points)

    def points_in(xmin, xmax, ymin, ymax, include_xmax, include_ymax):
        result = []
        for x, y, v in points:
            x_ok = xmin <= x and (x < xmax or (include_xmax and x <= xmax))
            y_ok = ymin <= y and (y < ymax or (include_ymax and y <= ymax))
            if x_ok and y_ok:
                result.append((x, y, v))
        return result

    width = 1.0 / n
    for i in range(n):
        xmin = i * width
        xmax = (i + 1) * width
        for j in range(n):
            ymin = j * width
            ymax = (j + 1) * width
            cell = points_in(xmin, xmax, ymin, ymax, i == n - 1, j == n - 1)
            var = variance(cell)
            if var > threshold:
                lines.append(
                    f"LEVEL1,{xmin:.3f},{xmax:.3f},{ymin:.3f},{ymax:.3f},{var:.3f}"
                )
                half_x = (xmax - xmin) / 2.0
                half_y = (ymax - ymin) / 2.0
                for si in range(2):
                    sxmin = xmin + si * half_x
                    sxmax = xmin + (si + 1) * half_x
                    for sj in range(2):
                        symin = ymin + sj * half_y
                        symax = ymin + (sj + 1) * half_y
                        sub = points_in(
                            sxmin,
                            sxmax,
                            symin,
                            symax,
                            i == n - 1 and si == 1,
                            j == n - 1 and sj == 1,
                        )
                        subvar = variance(sub)
                        if subvar > threshold:
                            lines.append(
                                f"LEVEL2,{sxmin:.3f},{sxmax:.3f},{symin:.3f},{symax:.3f},{subvar:.3f}"
                            )
    return lines


def nonempty_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def test_model_fit_c_exists():
    file_path = MODEL
    assert os.path.isfile(file_path), f"File {file_path} is missing."


def test_pipeline_sh_exists_and_executable():
    file_path = PIPELINE
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."


def test_refined_cells_txt_exists():
    file_path = OUTPUT
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you run pipeline.sh?"


def test_refined_cells_txt_content_and_pipeline_execution():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = run([PIPELINE])
    assert result.returncode == 0, f"pipeline.sh failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(OUTPUT), "pipeline.sh did not regenerate refined_cells.txt"

    with open(OUTPUT, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "LEVEL1,0.000,0.500,0.000,0.500,2.222",
        "LEVEL2,0.000,0.250,0.000,0.250,4.000",
    ]
    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {OUTPUT}, but found {len(lines)}."
    )
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."
        )


def test_c_program_compiles_and_handles_multiple_inputs():
    binary = os.path.join(tempfile.gettempdir(), "model_fit_submission")
    compile_result = run(["gcc", "-O3", MODEL, "-lm", "-o", binary])
    assert compile_result.returncode == 0, (
        f"model_fit.c did not compile:\n{compile_result.stdout}\n{compile_result.stderr}"
    )

    original = open(OBSERVATIONS, "rb").read()
    cases = [
        (
            "x,y,v\n"
            "0.0,0.0,0.0\n0.24,0.24,4.0\n0.25,0.25,8.0\n"
            "0.49,0.49,12.0\n0.5,0.5,1.0\n0.75,0.75,5.0\n"
            "1.0,1.0,9.0\n1.0,0.0,7.0\n0.0,1.0,3.0\n",
            2,
            3.0,
        ),
        (
            "x,y,v\n"
            "0.02,0.02,1.0\n0.10,0.12,6.0\n0.32,0.20,2.0\n"
            "0.34,0.34,9.0\n0.50,0.10,4.0\n0.66,0.30,12.0\n"
            "0.67,0.01,3.0\n0.99,0.32,11.0\n0.10,0.50,8.0\n"
            "0.30,0.66,1.0\n0.34,0.67,10.0\n0.60,0.60,2.0\n"
            "0.66,0.66,7.0\n0.67,0.67,0.0\n1.0,1.0,10.0\n"
            "1.0,0.5,5.0\n0.5,1.0,13.0\n0.0,1.0,4.0\n",
            3,
            2.25,
        ),
    ]

    try:
        for data, n, threshold in cases:
            with open(OBSERVATIONS, "w") as f:
                f.write(data)
            result = run([binary, str(n), str(threshold)])
            assert result.returncode == 0, (
                f"Program failed for N={n}, T={threshold}:\n{result.stderr}"
            )
            assert nonempty_lines(result.stdout) == expected_output(data, n, threshold)

        assert run([binary]).returncode != 0, "Program must reject missing arguments"
        assert run([binary, "2", "2.0", "extra"]).returncode != 0, (
            "Program must accept exactly two command-line arguments"
        )
    finally:
        with open(OBSERVATIONS, "wb") as f:
            f.write(original)
        if os.path.exists(binary):
            os.remove(binary)


def test_pipeline_uses_compiler_and_current_observations():
    data = (
        "x,y,v\n"
        "0.05,0.05,0.0\n0.20,0.20,10.0\n0.30,0.10,4.0\n"
        "0.10,0.30,8.0\n0.55,0.05,1.0\n0.95,0.45,9.0\n"
        "0.05,0.55,2.0\n0.45,0.95,6.0\n0.55,0.55,3.0\n"
        "1.0,1.0,11.0\n1.0,0.0,7.0\n0.0,1.0,5.0\n"
    )
    original_obs = open(OBSERVATIONS, "rb").read()
    original_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None
    try:
        with open(OBSERVATIONS, "w") as f:
            f.write(data)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)

        result = run(["bash", "-x", PIPELINE])
        assert result.returncode == 0, f"pipeline.sh failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(OUTPUT), "pipeline.sh did not create refined_cells.txt"
        with open(OUTPUT) as f:
            actual = nonempty_lines(f.read())
        assert actual == expected_output(data, 2, 2.0), (
            "pipeline.sh did not run the required N=2, T=2.0 computation"
        )

        trace_lines = result.stderr.splitlines()
        gcc_lines = [line for line in trace_lines if re.search(r"(?:^|[ /])gcc(?:\s|$)", line)]
        assert any(
            "-O3" in line and "-lm" in line and "model_fit.c" in line
            for line in gcc_lines
        ), "pipeline.sh must compile model_fit.c using gcc -O3 and -lm"
    finally:
        with open(OBSERVATIONS, "wb") as f:
            f.write(original_obs)
        if original_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
