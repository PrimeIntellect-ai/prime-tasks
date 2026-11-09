#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import struct
import subprocess
import zlib
from collections import Counter

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "simulate.c")
EXPERIMENT = os.path.join(HOME, "experiment.csv")
RESULTS = os.path.join(HOME, "results.txt")
SIM_DATA = os.path.join(HOME, "sim_data.csv")
PLOT = os.path.join(HOME, "plot.png")
BINARY = "/tmp/verify_simulate"
DT = 0.001
STEPS = 10000


def reference_curves():
    a1 = a2 = 1.0
    b1 = b2 = 0.0
    c1 = c2 = 0.0
    curve1 = [b1]
    curve2 = [b2]
    for _ in range(STEPS):
        na1 = a1 + DT * (-0.5 * a1)
        nb1 = b1 + DT * (0.5 * a1 - 0.2 * b1)
        nc1 = c1 + DT * (0.2 * b1)
        na2 = a2 + DT * (-0.5 * a2 * a2)
        nb2 = b2 + DT * (0.5 * a2 * a2 - 0.2 * b2)
        nc2 = c2 + DT * (0.2 * b2)
        a1, b1, c1 = na1, nb1, nc1
        a2, b2, c2 = na2, nb2, nc2
        curve1.append(b1)
        curve2.append(b2)
    return curve1, curve2


CURVE1, CURVE2 = reference_curves()


def read_experiment_bytes(data):
    text = data.decode("utf-8")
    rows = list(csv.reader(text.splitlines()))
    assert rows and len(rows[0]) >= 2
    return [(float(row[0]), float(row[1])) for row in rows[1:] if row]


def expected_for(points):
    vals1 = []
    vals2 = []
    observed = []
    for t, value in points:
        index = round(t / DT)
        assert 0 <= index <= STEPS and abs(t - index * DT) < 1e-9
        vals1.append(CURVE1[index])
        vals2.append(CURVE2[index])
        observed.append(value)
    mse1 = sum((x - y) ** 2 for x, y in zip(vals1, observed)) / len(points)
    mse2 = sum((x - y) ** 2 for x, y in zip(vals2, observed)) / len(points)
    best = "H1" if mse1 < mse2 else "H2"
    return mse1, mse2, best


def parse_results():
    assert os.path.isfile(RESULTS), f"File {RESULTS} does not exist."
    content = open(RESULTS, encoding="utf-8").read()
    match = re.fullmatch(
        r"MSE_H1: ([0-9]+\.[0-9]{6})\n"
        r"MSE_H2: ([0-9]+\.[0-9]{6})\n"
        r"Best: (H1|H2)\n?",
        content,
    )
    assert match, f"results.txt does not have the required exact format:\n{content}"
    return float(match.group(1)), float(match.group(2)), match.group(3)


def validate_sim_data():
    assert os.path.isfile(SIM_DATA), f"File {SIM_DATA} does not exist."
    numeric = []
    with open(SIM_DATA, newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle):
            if len(row) < 3:
                continue
            try:
                numeric.append([float(cell.strip()) for cell in row])
            except ValueError:
                continue
    assert len(numeric) >= 11, "sim_data.csv must contain a plotted time series, not a placeholder"
    width = len(numeric[0])
    numeric = [row for row in numeric if len(row) == width]
    assert width >= 3 and len(numeric) >= 11
    times = [row[0] for row in numeric]
    assert all(times[i] < times[i + 1] for i in range(len(times) - 1)), "Simulation times must increase"
    assert abs(times[0]) < 1e-6 and abs(times[-1] - 10.0) < 1e-6, "Simulation data must span t=0 through t=10"

    expected1 = []
    expected2 = []
    for t in times:
        index = round(t / DT)
        assert 0 <= index <= STEPS and abs(t - index * DT) < 1e-6, "Times do not lie on the required Euler grid"
        expected1.append(CURVE1[index])
        expected2.append(CURVE2[index])

    matching1 = []
    matching2 = []
    for column in range(1, width):
        values = [row[column] for row in numeric]
        if max(abs(x - y) for x, y in zip(values, expected1)) <= 1e-3:
            matching1.append(column)
        if max(abs(x - y) for x, y in zip(values, expected2)) <= 1e-3:
            matching2.append(column)
    assert matching1, "sim_data.csv contains no H1 B curve produced by the required Euler simulation"
    assert matching2, "sim_data.csv contains no H2 B curve produced by the required Euler simulation"
    assert any(a != b for a in matching1 for b in matching2), "H1 and H2 curves must be separate columns"


def run_case(points):
    for path in (RESULTS, SIM_DATA):
        if os.path.lexists(path):
            os.remove(path)
    proc = subprocess.run([BINARY], cwd=HOME, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=20)
    assert proc.returncode == 0, f"Compiled program failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    actual1, actual2, actual_best = parse_results()
    expected1, expected2, expected_best = expected_for(points)
    assert abs(actual1 - expected1) <= 5.1e-7, f"MSE_H1 is {actual1}, expected {expected1:.6f}"
    assert abs(actual2 - expected2) <= 5.1e-7, f"MSE_H2 is {actual2}, expected {expected2:.6f}"
    assert actual_best == expected_best, f"Best is {actual_best}, expected {expected_best}"
    validate_sim_data()


def write_hidden_case(model):
    rng = secrets.SystemRandom()
    points = []
    lines = ["Time,[B]"]
    curve = CURVE1 if model == "H1" else CURVE2
    for t in range(11):
        value = curve[t * 1000] + rng.uniform(-0.017, 0.017)
        value = float(f"{value:.6f}")
        points.append((float(t), value))
        lines.append(f"{t},{value:.6f}")
    with open(EXPERIMENT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    return points


@pytest.fixture(scope="session", autouse=True)
def compile_and_exercise_program():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    original = open(EXPERIMENT, "rb").read()
    compile_proc = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY, "-lm"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert compile_proc.returncode == 0, f"simulate.c does not compile:\n{compile_proc.stderr}"
    try:
        run_case(write_hidden_case("H1"))
        run_case(write_hidden_case("H2"))
        with open(EXPERIMENT, "wb") as handle:
            handle.write(original)
        run_case(read_experiment_bytes(original))
        yield
    finally:
        with open(EXPERIMENT, "wb") as handle:
            handle.write(original)


def test_simulate_c_exists():
    """Verify that the C program was created."""
    path = "/home/user/simulate.c"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_plot_png_exists():
    """Verify that the gnuplot output image was created."""
    path = "/home/user/plot.png"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_sim_data_csv_exists():
    """Verify that the simulation data CSV was created."""
    path = "/home/user/sim_data.csv"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_results_txt_content():
    """Verify the contents of results.txt match the expected MSE and Best hypothesis."""
    path = "/home/user/results.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    match_h1 = re.search(r"MSE_H1:\s*(0\.00305[7-9])", content)
    assert match_h1 is not None, f"Could not find matching MSE_H1 (expected ~0.003058) in {path}. Content:\n{content}"
    match_h2 = re.search(r"MSE_H2:\s*(0\.00003[0-1])", content)
    assert match_h2 is not None, f"Could not find matching MSE_H2 (expected ~0.000030) in {path}. Content:\n{content}"
    match_best = re.search(r"Best:\s*H2", content)
    assert match_best is not None, f"Could not find 'Best: H2' in {path}. Content:\n{content}"


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)


def test_plot_is_nonempty_png():
    data = open(PLOT, "rb").read()
    assert len(data) > 2000, "plot.png is empty or only a placeholder"
    assert data.startswith(b"\x89PNG\r\n\x1a\n"), "plot.png is not a PNG file"
    offset = 8
    idat = []
    width = height = bit_depth = color_type = interlace = None
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        assert offset + 12 + length <= len(data), "Truncated PNG"
        if kind == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            idat.append(payload)
        elif kind == b"IEND":
            break
        offset += length + 12
    assert width >= 200 and height >= 150, "Plot dimensions are too small"
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color_type)
    assert bit_depth == 8 and channels and interlace == 0 and idat, "Unsupported or malformed PNG"
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    assert len(raw) == height * (stride + 1), "Malformed PNG pixel data"
    rows = []
    pos = 0
    previous = bytearray(stride)
    for _ in range(height):
        filt = raw[pos]
        source = raw[pos + 1:pos + 1 + stride]
        pos += stride + 1
        row = bytearray(stride)
        for i, value in enumerate(source):
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filt == 0:
                result = value
            elif filt == 1:
                result = (value + left) & 255
            elif filt == 2:
                result = (value + up) & 255
            elif filt == 3:
                result = (value + ((left + up) // 2)) & 255
            elif filt == 4:
                result = (value + paeth(left, up, upper_left)) & 255
            else:
                raise AssertionError("Invalid PNG filter")
            row[i] = result
        rows.append(row)
        previous = row
    pixels = Counter()
    for row in rows:
        for i in range(0, len(row), channels):
            pixels[bytes(row[i:i + channels])] += 1
    assert len(pixels) >= 4, "plot.png does not contain plotted points and curves"
    assert sum(pixels.values()) - pixels.most_common(1)[0][1] >= 100, "plot.png appears blank"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
