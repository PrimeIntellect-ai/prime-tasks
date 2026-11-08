#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

HOME = "/home/user"


def run(cmd, timeout=30):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout, check=True)


def canonical_dataset():
    lines = ["x,y"]
    xs, ys = [], []
    for i in range(101):
        x = i * 0.1
        y = x
        for _ in range(10):
            y = y - (y**3 + y - x) / (3 * y**2 + 1)
        xs.append(x)
        ys.append(y)
        lines.append(f"{x:.4f},{y:.4f}")
    return ("\n".join(lines) + "\n").encode(), xs, ys


def regression(points):
    n = len(points)
    sx = sum(x for x, _ in points)
    sy = sum(y for _, y in points)
    sxy = sum(x * y for x, y in points)
    sxx = sum(x * x for x, _ in points)
    denominator = n * sxx - sx * sx
    assert n >= 2 and abs(denominator) > 1e-12
    m = (n * sxy - sx * sy) / denominator
    c = (sy - m * sx) / n
    return m, c


def parse_dataset(path):
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().strip().split("\n")
    assert len(lines) == 102, f"Expected 102 lines in {path}, found {len(lines)}."
    assert lines[0] == "x,y", f"Expected header 'x,y' in {path}, found '{lines[0]}'."
    points = []
    for line in lines[1:]:
        fields = line.split(",")
        assert len(fields) == 2, f"Invalid CSV row: {line!r}"
        x, y = map(float, fields)
        assert math.isfinite(x) and math.isfinite(y)
        points.append((x, y))
    return points


def check_regression(path, points, also_check_original=False):
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original substantive checks.
    m_match = re.search(r"m=([0-9\.\-]+)", content)
    c_match = re.search(r"c=([0-9\.\-]+)", content)
    assert m_match, f"Could not find 'm=<value>' in {path}."
    assert c_match, f"Could not find 'c=<value>' in {path}."

    # The instruction requires exactly these two lines and four decimal places.
    exact = re.fullmatch(r"m=(-?\d+\.\d{4})\nc=(-?\d+\.\d{4})\n?", content)
    assert exact, f"{path} is not in the required exact four-decimal format."
    m_val, c_val = map(float, exact.groups())
    expected_m, expected_c = regression(points)
    assert m_val == float(f"{expected_m:.4f}"), (m_val, expected_m)
    assert c_val == float(f"{expected_c:.4f}"), (c_val, expected_c)

    if also_check_original:
        _, xs, ys = canonical_dataset()
        n = len(xs)
        sum_x = sum(xs)
        sum_y = sum(ys)
        sum_xy = sum(x*y for x, y in zip(xs, ys))
        sum_xx = sum(x*x for x in xs)
        original_m = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x**2)
        original_c = (sum_y - original_m * sum_x) / n
        assert math.isclose(m_val, original_m, abs_tol=0.001)
        assert math.isclose(c_val, original_c, abs_tol=0.001)


def check_svg(path, point_count):
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    lower = content.lower()
    assert "<svg" in lower, f"{path} does not contain '<svg' element."
    assert "<line" in lower, f"{path} does not contain '<line' element."
    assert "<circle" in lower, f"{path} does not contain '<circle' element."

    root = ET.fromstring(content)
    assert root.tag.split("}")[-1].lower() == "svg"
    circles = [e for e in root.iter() if e.tag.split("}")[-1].lower() == "circle"]
    lines = [e for e in root.iter() if e.tag.split("}")[-1].lower() == "line"]
    assert len(circles) >= point_count, f"Expected at least {point_count} plotted circles."
    assert lines, "Expected a fitted regression line."
    for circle in circles[:point_count]:
        values = [float(circle.attrib[k]) for k in ("cx", "cy", "r")]
        assert all(math.isfinite(v) for v in values) and values[2] > 0
    valid_line = False
    for line in lines:
        try:
            x1, y1, x2, y2 = [float(line.attrib[k]) for k in ("x1", "y1", "x2", "y2")]
            if all(math.isfinite(v) for v in (x1, y1, x2, y2)) and (x1 != x2 or y1 != y2):
                valid_line = True
        except (KeyError, ValueError):
            pass
    assert valid_line, "Regression line lacks finite, non-degenerate coordinates."
    return content


def write_dynamic_dataset(seed):
    rng = random.SystemRandom()
    start = rng.uniform(-3.0, 1.0) + seed
    step = rng.uniform(0.035, 0.095)
    rows = ["x,y"]
    for i in range(101):
        x = start + i * step
        y = x
        for _ in range(10):
            y -= (y**3 + y - x) / (3*y*y + 1)
        rows.append(f"{x:.4f},{y:.4f}")
    with open(f"{HOME}/dataset.csv", "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")


def test_complete_workflow():
    exe = f"{HOME}/data_gen"
    assert os.path.isfile(exe), f"File {exe} does not exist."
    assert os.access(exe, os.X_OK), f"File {exe} is not executable."
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe} is not a compiled ELF executable."

    expected_bytes, _, _ = canonical_dataset()
    submitted_output = run([exe], timeout=10).stdout
    assert submitted_output == expected_bytes, "data_gen output does not match the required generator."

    # Confirm the supplied C source still compiles and has the same required behavior.
    with tempfile.TemporaryDirectory() as td:
        ref = os.path.join(td, "data_gen")
        run(["gcc", f"{HOME}/data_gen.c", "-lm", "-o", ref], timeout=30)
        assert run([ref], timeout=10).stdout == expected_bytes

    # Preserve the original final-artifact checks before regenerating anything.
    points = parse_dataset(f"{HOME}/dataset.csv")
    assert open(f"{HOME}/dataset.csv", "rb").read() == expected_bytes
    check_regression(f"{HOME}/regression.txt", points, also_check_original=True)
    check_svg(f"{HOME}/plot.svg", len(points))

    go_file = f"{HOME}/process.go"
    assert os.path.isfile(go_file), f"File {go_file} does not exist."
    with open(go_file, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.search(r"(?m)^\s*package\s+main\s*$", source)
    assert re.search(r"\bfunc\s+main\s*\(", source)

    # Execute the submitted Go program on unpredictable datasets and derive the
    # expected coefficients from the actual CSV values it was required to read.
    plots = []
    for seed in (0.0, 7.0):
        write_dynamic_dataset(seed)
        run(["go", "run", go_file], timeout=45)
        points = parse_dataset(f"{HOME}/dataset.csv")
        check_regression(f"{HOME}/regression.txt", points)
        plots.append(check_svg(f"{HOME}/plot.svg", len(points)))
    assert plots[0] != plots[1], "plot.svg did not respond to changed input data."

    # Finally execute the complete requested pipeline and validate its products.
    with open(f"{HOME}/dataset.csv", "wb") as f:
        f.write(run([exe], timeout=10).stdout)
    run(["go", "run", go_file], timeout=45)
    points = parse_dataset(f"{HOME}/dataset.csv")
    assert open(f"{HOME}/dataset.csv", "rb").read() == expected_bytes
    check_regression(f"{HOME}/regression.txt", points, also_check_original=True)
    check_svg(f"{HOME}/plot.svg", len(points))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
