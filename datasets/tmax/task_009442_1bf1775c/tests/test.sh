#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import ctypes.util
import hashlib
import math
import os
import re
import struct
import subprocess

import pytest

HOME = "/home/user"
CSV = os.path.join(HOME, "ml_features.csv")
SUMMARY = os.path.join(HOME, "summary.txt")
PNG = os.path.join(HOME, "features.png")
FLOAT_RE = re.compile(r"^[+-]?(?:\d+\.\d{6})$")


def run_checked(command, timeout=30):
    result = subprocess.run(
        command,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command failed: {' '.join(command)}\n{result.stdout}"


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_run_submission():
    source = os.path.join(HOME, "generate_features.c")
    executable = os.path.join(HOME, "generate_features")
    script = os.path.join(HOME, "plot_features.gp")

    # Preserve the original existence/type assertions before rebuilding.
    assert os.path.isfile(source), "C source file /home/user/generate_features.c is missing."
    assert os.path.isfile(executable), "Executable /home/user/generate_features is missing."
    assert os.access(executable, os.X_OK), "/home/user/generate_features is not executable."
    assert os.path.isfile(script), "Gnuplot script /home/user/plot_features.gp is missing."

    # Compile the submitted source using the command required by the task, then
    # remove stale outputs so only execution of the submitted artifacts can make them.
    run_checked(["gcc", "-o", executable, source, "-lm"])
    for path in (CSV, SUMMARY, PNG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_checked([executable])
    assert os.path.isfile(CSV), f"{CSV} is missing after running the C program."
    assert os.path.isfile(SUMMARY), f"{SUMMARY} is missing after running the C program."

    run_checked(["gnuplot", script])


def f32(value):
    return struct.unpack("=f", struct.pack("=f", value))[0]


def expected_pdf():
    libm_name = ctypes.util.find_library("m")
    assert libm_name, "Unable to locate libm for independent calculation."
    libm = ctypes.CDLL(libm_name)
    libm.sinf.argtypes = [ctypes.c_float]
    libm.sinf.restype = ctypes.c_float
    libm.cosf.argtypes = [ctypes.c_float]
    libm.cosf.restype = ctypes.c_float

    counts = [0] * 100
    valid = 0
    state = 12345
    width = f32(0.04)
    for _ in range(100000):
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        u = f32(f32(state) / f32(4294967296.0))
        x = f32(f32(5.0) * u)
        twice_x = f32(f32(2.0) * x)
        y = f32(libm.sinf(x) + libm.cosf(twice_x))
        if -2.0 <= y <= 2.0:
            index = int(f32(f32(y + f32(2.0)) / width))
            if index == 100 and y == 2.0:
                index = 99
            if 0 <= index < 100:
                counts[index] += 1
                valid += 1

    assert valid > 0
    return [count / (valid * 0.04) for count in counts]


def read_csv():
    assert os.path.isfile(CSV), f"{CSV} is missing."
    with open(CSV, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()

    assert lines, "CSV file is empty."
    assert lines[0] == "y_bin_center,pdf,pdf_derivative", f"Invalid CSV header: {lines[0]}"
    data_lines = [line for line in lines[1:] if line.strip()]
    assert len(data_lines) == 100, f"Expected 100 data rows in CSV, found {len(data_lines)}."

    rows = []
    for number, line in enumerate(data_lines, start=2):
        parts = line.split(",")
        assert len(parts) == 3, f"CSV row {number} must have exactly 3 columns."
        assert all(FLOAT_RE.fullmatch(part) for part in parts), (
            f"CSV row {number} must contain values formatted to exactly 6 decimal places."
        )
        values = tuple(float(part) for part in parts)
        assert all(math.isfinite(value) for value in values), f"Non-finite value in CSV row {number}."
        rows.append(values)
    return rows


def assert_valid_png(path):
    assert os.path.isfile(path), "PNG image /home/user/features.png is missing."
    assert os.path.getsize(path) > 24, "PNG image /home/user/features.png is empty or truncated."
    with open(path, "rb") as handle:
        header = handle.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", "features.png is not a PNG file."
    assert header[12:16] == b"IHDR", "features.png has no valid PNG IHDR chunk."
    width, height = struct.unpack(">II", header[16:24])
    assert width > 0 and height > 0, "features.png has invalid dimensions."


def test_c_source_exists():
    assert os.path.isfile("/home/user/generate_features.c"), "C source file /home/user/generate_features.c is missing."


def test_executable_exists():
    assert os.path.isfile("/home/user/generate_features"), "Executable /home/user/generate_features is missing."
    assert os.access("/home/user/generate_features", os.X_OK), "/home/user/generate_features is not executable."


def test_csv_exists_and_format_and_values():
    rows = read_csv()
    expected = expected_pdf()

    for i, (center, pdf, derivative) in enumerate(rows):
        expected_center = -2.0 + (i + 0.5) * 0.04
        assert abs(center - expected_center) <= 5.1e-7, (
            f"Incorrect bin center in bin {i}: got {center}, expected {expected_center:.6f}."
        )
        assert pdf >= 0.0, f"PDF is negative in bin {i}."
        # This tolerance permits minor float-vs-double boundary differences while
        # still requiring the deterministic LCG histogram and transformed density.
        assert abs(pdf - expected[i]) <= 0.005, (
            f"Incorrect histogram PDF in bin {i}: got {pdf}, expected about {expected[i]:.6f}."
        )

        if i < 99:
            from_csv = (rows[i + 1][1] - pdf) / 0.04
            assert abs(derivative - from_csv) <= 3e-5, (
                f"Incorrect forward-difference derivative in bin {i}: got {derivative}, "
                f"expected {from_csv:.6f} from adjacent PDF values."
            )
            expected_derivative = (expected[i + 1] - expected[i]) / 0.04
            assert abs(derivative - expected_derivative) <= 0.30, (
                f"Derivative in bin {i} is inconsistent with the deterministic histogram."
            )
        else:
            assert abs(derivative) <= 5.1e-7, "The derivative in the final bin must be 0."

    area = sum(row[1] * 0.04 for row in rows)
    assert abs(area - 1.0) <= 2e-5, f"CSV PDF integrates to {area}, not 1.0."


def test_summary_txt():
    assert os.path.isfile(SUMMARY), f"{SUMMARY} is missing."
    with open(SUMMARY, "r", encoding="utf-8") as handle:
        content = handle.read().strip()

    match = re.fullmatch(r"Integral:\s*([+-]?\d+\.\d{6})", content)
    assert match is not None, "summary.txt must be a single 'Integral: <value>' line with 6 decimals."
    integral_val = float(match.group(1))
    assert 0.99 <= integral_val <= 1.01, (
        f"Integral value {integral_val} is out of expected bounds (should be ~1.0)."
    )
    csv_area = sum(row[1] * 0.04 for row in read_csv())
    assert abs(integral_val - csv_area) <= 2e-5, (
        f"summary integral {integral_val} does not match the CSV left-Riemann sum {csv_area}."
    )


def test_gnuplot_script_exists_and_uses_lines():
    script_path = "/home/user/plot_features.gp"
    assert os.path.isfile(script_path), "Gnuplot script /home/user/plot_features.gp is missing."
    with open(script_path, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read().lower()
    assert "ml_features.csv" in text, "Gnuplot script does not read ml_features.csv."
    line_style = re.search(r"(?:with|w)\s+(?:lines|linespoints|l|lp)\b", text)
    default_line_style = re.search(r"set\s+style\s+data\s+(?:lines|linespoints)\b", text)
    assert line_style or default_line_style, "Gnuplot script must plot the PDF as a line graph."


def test_png_exists_and_plot_depends_on_columns_1_and_2():
    assert_valid_png(PNG)
    script = os.path.join(HOME, "plot_features.gp")
    with open(CSV, "r", encoding="utf-8") as handle:
        original = handle.read()
    baseline_hash = hashlib.sha256(open(PNG, "rb").read()).digest()
    lines = original.splitlines()

    try:
        # Changing only column 2 must alter the rendered graph.
        changed_pdf = [lines[0]]
        for i, line in enumerate(lines[1:]):
            x, pdf, derivative = line.split(",")
            new_pdf = float(pdf) * (0.25 if i % 2 else 1.75) + (0.02 if i % 3 == 0 else 0.0)
            changed_pdf.append(f"{x},{new_pdf:.6f},{derivative}")
        with open(CSV, "w", encoding="utf-8") as handle:
            handle.write("\n".join(changed_pdf) + "\n")
        if os.path.exists(PNG):
            os.remove(PNG)
        run_checked(["gnuplot", script])
        assert_valid_png(PNG)
        pdf_hash = hashlib.sha256(open(PNG, "rb").read()).digest()
        assert pdf_hash != baseline_hash, "Plot does not depend on PDF column 2."

        # Changing only column 1 must also alter the rendered graph.
        changed_x = [lines[0]]
        for i, line in enumerate(lines[1:]):
            x, pdf, derivative = line.split(",")
            new_x = -1.98 + ((i * 37) % 100) * 0.04
            changed_x.append(f"{new_x:.6f},{pdf},{derivative}")
        with open(CSV, "w", encoding="utf-8") as handle:
            handle.write("\n".join(changed_x) + "\n")
        if os.path.exists(PNG):
            os.remove(PNG)
        run_checked(["gnuplot", script])
        assert_valid_png(PNG)
        x_hash = hashlib.sha256(open(PNG, "rb").read()).digest()
        assert x_hash != baseline_hash, "Plot does not depend on y_bin_center column 1."
    finally:
        with open(CSV, "w", encoding="utf-8") as handle:
            handle.write(original)
        if os.path.exists(PNG):
            os.remove(PNG)
        run_checked(["gnuplot", script])

    assert_valid_png(PNG)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
