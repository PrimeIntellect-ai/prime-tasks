#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import hashlib
import os
import subprocess

import matplotlib.image as mpimg
import numpy as np
from scipy.stats import ttest_ind

SCRIPT = "/home/user/analyze_metrics.py"
DATA = "/home/user/data/metrics.csv"
RESULTS = "/home/user/results.txt"
IMAGE = "/home/user/histogram.png"


def test_script_exists():
    """Check if the analyze_metrics.py script exists."""
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."


def test_agg_is_configured_before_pyplot():
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    matplotlib_aliases = {"matplotlib"}
    use_aliases = set()
    pyplot_lines = []
    agg_lines = []

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "matplotlib":
                    matplotlib_aliases.add(alias.asname or "matplotlib")
                if alias.name == "matplotlib.pyplot":
                    pyplot_lines.append(node.lineno)
        elif isinstance(node, ast.ImportFrom) and node.module == "matplotlib":
            for alias in node.names:
                if alias.name == "pyplot":
                    pyplot_lines.append(node.lineno)
                if alias.name == "use":
                    use_aliases.add(alias.asname or "use")
        elif isinstance(node, ast.Call) and node.args:
            func = node.func
            is_use = (
                isinstance(func, ast.Attribute)
                and func.attr == "use"
                and isinstance(func.value, ast.Name)
                and func.value.id in matplotlib_aliases
            ) or (isinstance(func, ast.Name) and func.id in use_aliases)
            if is_use and isinstance(node.args[0], ast.Constant):
                if str(node.args[0].value).lower() == "agg":
                    agg_lines.append(node.lineno)
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value, ast.Constant) and str(value.value).lower() == "agg":
                for target in targets:
                    text = ast.unparse(target).replace('"', "'")
                    if "MPLBACKEND" in text or ("rcParams" in text and "backend" in text):
                        agg_lines.append(node.lineno)

    assert agg_lines, "The script must explicitly configure matplotlib to use the Agg backend."
    if pyplot_lines:
        assert min(agg_lines) < min(pyplot_lines), "Agg must be configured before importing pyplot."


def run_script():
    for path in (RESULTS, IMAGE):
        if os.path.lexists(path):
            os.remove(path)
    env = os.environ.copy()
    env.pop("DISPLAY", None)
    env.pop("MPLBACKEND", None)
    completed = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f"analyze_metrics.py failed in a headless environment.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def read_result_lines():
    assert os.path.exists(RESULTS), f"Results file {RESULTS} is missing."
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a file."
    with open(RESULTS, "r", encoding="utf-8") as f:
        content = f.read().strip()
    return content, [line.strip() for line in content.splitlines() if line.strip()]


def validate_png():
    assert os.path.exists(IMAGE), f"Image file {IMAGE} is missing."
    assert os.path.isfile(IMAGE), f"{IMAGE} is not a file."
    assert os.path.getsize(IMAGE) > 0, f"Image file {IMAGE} is empty."
    with open(IMAGE, "rb") as f:
        data = f.read()
    assert data.startswith(b"\x89PNG\r\n\x1a\n"), "histogram.png is not a PNG file."
    try:
        pixels = np.asarray(mpimg.imread(IMAGE))
    except Exception as exc:
        raise AssertionError(f"histogram.png is not a readable PNG: {exc}")
    assert pixels.ndim in (2, 3) and pixels.shape[0] > 10 and pixels.shape[1] > 10
    rgb = pixels[..., :3] if pixels.ndim == 3 else pixels
    assert np.isfinite(rgb).all(), "histogram.png contains invalid pixel values."
    assert float(np.max(rgb) - np.min(rgb)) > 0.05, "histogram.png appears blank."
    return hashlib.sha256(data).hexdigest()


def write_dataset(groups):
    with open(DATA, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["server_id", "timestamp", "response_time"])
        index = 0
        for server_id, values in groups.items():
            for value in values:
                writer.writerow([server_id, f"2024-01-01T00:{index:02d}:00", value])
                index += 1


def expected_for(groups):
    target = np.asarray(groups["srv_target"], dtype=float)
    candidates = {k: np.asarray(v, dtype=float) for k, v in groups.items() if k != "srv_target"}
    closest = min(candidates, key=lambda k: abs(float(np.mean(candidates[k])) - float(np.mean(target))))
    p_value = ttest_ind(target, candidates[closest], equal_var=True).pvalue
    return [f"closest_server: {closest}", f"p_value: {p_value:.4f}"]


def test_script_execution_results_and_histogram():
    with open(DATA, "rb") as f:
        original_data = f.read()

    image_hashes = []
    try:
        # Execute against the shipped dataset, then retain the original exact assertions.
        run_script()
        content, actual_lines = read_result_lines()
        expected_content = "closest_server: srv_beta\np_value: 0.0248"
        expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]
        assert actual_lines == expected_lines, (
            f"Contents of {RESULTS} do not match the expected output. Got:\n{content}"
        )
        image_hashes.append(validate_png())

        datasets = [
            {
                "srv_target": [10, 11, 12, 13, 14, 15],
                "node_red": [10.5, 11.5, 12.5, 13.5, 14.5, 15.5],
                "node_far": [30, 31, 32, 33, 34, 35],
                "node_low": [-8, -7, -6, -5, -4, -3],
            },
            {
                "srv_target": [0, 0, 0, 0, 20, 20, 20, 20],
                "node_blue": [7, 9, 10, 11, 13],
                "node_high": [45, 50, 55, 60, 65],
                "node_negative": [-25, -20, -15, -10, -5],
            },
        ]

        for groups in datasets:
            write_dataset(groups)
            run_script()
            content, actual_lines = read_result_lines()
            expected_lines = expected_for(groups)
            assert actual_lines == expected_lines, (
                "The script did not derive the closest server and equal-variance "
                f"two-sample t-test result from the current CSV. Got:\n{content}\n"
                f"Expected:\n" + "\n".join(expected_lines)
            )
            image_hashes.append(validate_png())

        assert len(set(image_hashes)) == len(image_hashes), (
            "histogram.png did not change when the plotted response-time data changed."
        )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
