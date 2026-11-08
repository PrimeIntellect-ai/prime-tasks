#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess
import time

import matplotlib.image as mpimg
import numpy as np
import requests

SIM_SOURCE = "/home/user/simulate.c"
PLOT_PATH = "/home/user/return_distribution.png"
GRAPH_TEXT = "0 1\n1 2\n2 3\n3 0\n1 4\n"
GRAPH_EDGES = [(0, 1), (1, 2), (2, 3), (3, 0), (1, 4)]


def theoretical_return_time(edges, node=0):
    degree = sum(1 for u, v in edges if u == node or v == node)
    assert degree > 0
    return 2.0 * len(edges) / degree


def test_c_simulation_exists_compiles_and_runs():
    assert os.path.isfile(SIM_SOURCE), f"{SIM_SOURCE} is missing"
    assert os.path.getsize(SIM_SOURCE) > 100, "simulate.c is implausibly small"

    source = open(SIM_SOURCE, "r", encoding="utf-8", errors="replace").read()
    compact = re.sub(r"[\s'_]", "", source).lower()
    assert ("1000000" in compact or "1e6" in compact or "1000*1000" in compact), \
        "simulate.c does not contain a 1,000,000-walk simulation count"
    assert re.search(r"\b(rand|random|drand48|rng|xorshift|pcg)\w*\s*\(", source, re.I), \
        "simulate.c contains no apparent random-number generation"
    assert re.search(r"\b(fscanf|scanf|getline|fgets|read)\s*\(", source), \
        "simulate.c does not appear to read edge data"
    assert re.search(r"\b(for|while|do)\b", source), "simulate.c contains no simulation loop"

    exe = "/tmp/verifier_simulate"
    build = subprocess.run(
        ["gcc", "-O2", "-std=c11", SIM_SOURCE, "-o", exe, "-lm"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, f"simulate.c does not compile:\n{build.stderr}"

    edge_file = "/tmp/verifier_edges.txt"
    with open(edge_file, "w", encoding="ascii") as f:
        f.write(GRAPH_TEXT)

    run = subprocess.run(
        [exe, edge_file], input=GRAPH_TEXT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        cwd="/home/user", timeout=60
    )
    assert run.returncode == 0, f"compiled simulation failed:\n{run.stdout}"

    numbers = [float(x) for x in re.findall(
        r"(?<![A-Za-z])[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", run.stdout
    )]
    assert numbers, "compiled simulation did not report a numeric result on stdout"
    measured = numbers[-1]
    expected = theoretical_return_time(GRAPH_EDGES)
    assert math.isfinite(measured), "simulation result is not finite"
    assert abs(measured - expected) <= 0.12, \
        f"executed C simulation reported {measured}, expected approximately {expected}"


def test_return_distribution_plot_exists():
    assert os.path.isfile(PLOT_PATH), "/home/user/return_distribution.png is missing"
    assert os.path.getsize(PLOT_PATH) > 1000, "return_distribution.png is empty or implausibly small"
    with open(PLOT_PATH, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "return_distribution.png is not a PNG file"
    image = np.asarray(mpimg.imread(PLOT_PATH))
    assert image.ndim in (2, 3), "return_distribution.png cannot be decoded as an image"
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "distribution plot is too small"
    assert float(np.std(image)) > 0.01, "distribution plot appears blank"
    assert len(np.unique((image * 255).astype(np.uint8))) >= 8, "distribution plot lacks meaningful content"


def test_api_stats():
    url = "http://127.0.0.1:8080/stats"
    max_retries = 5
    response = None
    for _ in range(max_retries):
        try:
            response = requests.get(url, timeout=2)
            break
        except requests.exceptions.RequestException:
            time.sleep(1)

    assert response is not None, "Failed to connect to the HTTP server at 0.0.0.0:8080"
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"

    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        assert False, "Response is not valid JSON"

    assert "average_return_time" in data, "Key 'average_return_time' missing in JSON response"
    assert "error" in data, "Key 'error' missing in JSON response"

    avg_return_time = float(data["average_return_time"])
    error = float(data["error"])
    assert math.isfinite(avg_return_time) and math.isfinite(error), "API metrics must be finite"

    # Preserve the original acceptance bounds.
    assert 4.90 <= avg_return_time <= 5.10, \
        f"average_return_time {avg_return_time} is not between 4.90 and 5.10"
    assert 0.0 <= error <= 0.10, f"error {error} is not between 0.0 and 0.10"

    with open("/app/reference.csv", newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    reference = float(next(row["expected_time"] for row in rows if int(row["node"]) == 0))
    independently_derived = theoretical_return_time(GRAPH_EDGES)
    assert abs(reference - independently_derived) < 1e-9, \
        "reference value does not match the graph's theoretical return time"
    assert abs(error - abs(avg_return_time - reference)) <= 0.002, \
        "API error is inconsistent with average_return_time and reference.csv"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
