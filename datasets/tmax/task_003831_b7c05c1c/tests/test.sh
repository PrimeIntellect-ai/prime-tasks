#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import struct
import subprocess

import pytest

HOME = "/home/user"


@pytest.fixture(scope="session", autouse=True)
def build_run_and_plot():
    source = os.path.join(HOME, "integrator.go")
    assert os.path.isfile(source), f"{source} is missing."
    assert not os.path.islink(source), "integrator.go must be a regular source file, not a symlink."

    with open(source, "r", encoding="utf-8") as f:
        code = f.read()

    # Ignore comments when checking that the requested adaptation was actually fixed.
    uncommented = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    uncommented = re.sub(r"//.*", "", uncommented)
    fixed_update = re.search(
        r"(?:dt\s*=\s*dt\s*\*|dt\s*\*=)\s*math\.Sqrt\s*\(\s*tol\s*/\s*errEst\s*\)",
        uncommented,
    )
    assert fixed_update, "integrator.go does not shrink dt using sqrt(tol/errEst)."

    dataset = os.path.join(HOME, "dataset.csv")
    png = os.path.join(HOME, "plot.png")
    for path in (dataset, png):
        if os.path.lexists(path):
            os.remove(path)

    binary = "/tmp/submitted_integrator"
    subprocess.run(
        ["go", "build", "-o", binary, source],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    subprocess.run(
        [binary],
        check=True,
        timeout=30,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(dataset), "Executing integrator.go did not create dataset.csv."

    gp_file = os.path.join(HOME, "plot.gp")
    assert os.path.isfile(gp_file), f"{gp_file} is missing."
    subprocess.run(
        ["gnuplot", gp_file],
        check=True,
        timeout=30,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(png), "Executing plot.gp did not create plot.png."


def expected_trajectory():
    t = 0.0
    y = 1.0
    t_end = 2.0
    dt = 0.1
    tol = 1e-4
    rows = [(t, y)]

    for _ in range(1000000):
        if not t < t_end:
            break
        if t + dt > t_end:
            dt = t_end - t

        k1 = -15.0 * y
        k2 = -15.0 * (y + dt * k1)
        y1 = y + dt * 0.5 * (k1 + k2)
        y2 = y + dt * k1
        err_est = abs(y1 - y2)
        if err_est == 0:
            err_est = 1e-10

        if err_est <= tol:
            t += dt
            y = y1
            rows.append((t, y))

        dt = dt * math.sqrt(tol / err_est)
        if dt > 0.5:
            dt = 0.5
        if dt < 1e-5:
            break
    else:
        pytest.fail("Reference integration did not terminate.")

    assert abs(rows[-1][0] - 2.0) < 1e-12
    return rows


def read_dataset():
    csv_file = os.path.join(HOME, "dataset.csv")
    with open(csv_file, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        rows = list(reader)
    return header, rows


def test_dataset_csv_exists_and_valid():
    """Check existence, original shape assertions, and the complete ODE trajectory."""
    csv_file = os.path.join(HOME, "dataset.csv")
    assert os.path.isfile(csv_file), f"{csv_file} is missing."

    header, rows = read_dataset()
    assert header == ["t", "y"], "dataset.csv header should be 't,y'."
    assert len(rows) > 0, "dataset.csv is empty."
    assert all(len(row) == 2 for row in rows), "Every dataset row must contain exactly t and y."

    actual = []
    for row in rows:
        t, y = map(float, row)
        assert math.isfinite(t) and math.isfinite(y), "dataset.csv contains NaN or Inf."
        actual.append((t, y))

    last_t = actual[-1][0]
    assert abs(last_t - 2.0) < 1e-3, f"Integration did not reach t=2.0. Last t was {last_t}."
    assert actual[0] == (0.0, 1.0), "The trajectory must begin at y(0)=1."
    assert all(actual[i][0] > actual[i - 1][0] for i in range(1, len(actual))), \
        "Integration times must be strictly increasing."

    expected = expected_trajectory()
    assert len(actual) == len(expected), \
        f"Unexpected number of accepted integration steps: {len(actual)} instead of {len(expected)}."
    for i, ((got_t, got_y), (want_t, want_y)) in enumerate(zip(actual, expected)):
        # The supplied Go program writes six digits after the decimal point.
        assert abs(got_t - want_t) <= 5.1e-7, f"Incorrect t at dataset row {i + 2}."
        assert abs(got_y - want_y) <= 5.1e-7, f"Incorrect ODE value at dataset row {i + 2}."


def test_plot_gp_exists():
    """Check the original keywords and that the script plots dataset y versus t with lines."""
    gp_file = os.path.join(HOME, "plot.gp")
    assert os.path.isfile(gp_file), f"{gp_file} is missing."

    with open(gp_file, "r", encoding="utf-8") as f:
        content = f.read().lower()
    assert "dataset.csv" in content, "plot.gp does not reference dataset.csv."
    assert "plot" in content, "plot.gp does not contain a plot command."
    assert "png" in content, "plot.gp does not set the terminal to png."

    active = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert re.search(r"(?m)^\s*set\s+terminal\s+.*png", active), \
        "plot.gp must select a PNG terminal."
    assert re.search(r"(?m)^\s*set\s+output\s+['\"](?:/home/user/)?plot\.png['\"]", active), \
        "plot.gp must output to /home/user/plot.png."
    assert re.search(r"(?m)^\s*plot\s+[^\n]*dataset\.csv[^\n]*\bwith\s+lines\b", active), \
        "plot.gp must plot dataset.csv with lines."


def test_plot_png_exists():
    """Check the original signature assertion and the structure of the freshly generated PNG."""
    png_file = os.path.join(HOME, "plot.png")
    assert os.path.isfile(png_file), f"{png_file} is missing."

    with open(png_file, "rb") as f:
        data = f.read()
    header = data[:8]
    assert header == b'\x89PNG\r\n\x1a\n', f"{png_file} is not a valid PNG file."
    assert len(data) > 100, "plot.png contains only a PNG header or is otherwise empty."

    pos = 8
    chunks = []
    width = height = 0
    while pos + 12 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        chunk_type = data[pos + 4:pos + 8]
        end = pos + 12 + length
        assert end <= len(data), "plot.png contains a truncated PNG chunk."
        chunks.append(chunk_type)
        if chunk_type == b"IHDR":
            assert length == 13, "plot.png has an invalid IHDR chunk."
            width, height = struct.unpack(">II", data[pos + 8:pos + 16])
        pos = end
        if chunk_type == b"IEND":
            break

    assert chunks and chunks[0] == b"IHDR", "plot.png is missing its IHDR chunk."
    assert b"IDAT" in chunks and chunks[-1] == b"IEND", "plot.png lacks complete image data."
    assert width > 1 and height > 1, "plot.png has invalid image dimensions."


def test_final_y_txt():
    """Keep the original final-value checks and match the executed integrator output."""
    txt_file = os.path.join(HOME, "final_y.txt")
    assert os.path.isfile(txt_file), f"{txt_file} is missing."

    with open(txt_file, "r") as f:
        content = f.read().strip()

    try:
        final_y = float(content)
    except ValueError:
        assert False, f"{txt_file} does not contain a valid float."

    assert math.isfinite(final_y), f"{txt_file} contains NaN or Inf."
    assert abs(final_y) < 1e-5, f"Final y value {final_y} is too large. Expected close to 0."

    csv_file = os.path.join(HOME, "dataset.csv")
    if os.path.isfile(csv_file):
        with open(csv_file, "r") as f:
            rows = list(csv.reader(f))
            if len(rows) > 1:
                last_y_csv = float(rows[-1][1])
                assert abs(final_y - last_y_csv) < 1e-9, \
                    "final_y.txt does not match the last y value in dataset.csv."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
