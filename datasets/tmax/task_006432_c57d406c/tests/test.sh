#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import secrets
import subprocess
from pathlib import Path

from PIL import Image

SCRIPT_PATH = Path("/home/user/run_analysis.py")
FASTA_PATH = Path("/home/user/protein.fasta")
JSON_PATH = Path("/home/user/analysis.json")
PLOT_PATH = Path("/home/user/distance_distribution.png")
REQUIRED_KEYS = {
    "sequence_length",
    "mc_mean_squared_distance",
    "analytical_mean_squared_distance",
    "relative_error",
}


def check_script():
    assert SCRIPT_PATH.exists(), f"Error: {SCRIPT_PATH} not found."
    assert SCRIPT_PATH.is_file(), f"Error: {SCRIPT_PATH} is not a regular file."
    source = SCRIPT_PATH.read_text(encoding="utf-8")
    assert source.strip(), f"Error: {SCRIPT_PATH} is empty."
    try:
        tree = ast.parse(source, filename=str(SCRIPT_PATH))
    except SyntaxError as exc:
        raise AssertionError(f"Error: {SCRIPT_PATH} is not valid Python: {exc}")

    # The requested artifact must contain the 10,000-walk simulation and call a
    # randomness API, rather than merely writing self-reported constants.
    assert any(
        isinstance(node, ast.Constant)
        and isinstance(node.value, (int, float))
        and not isinstance(node.value, bool)
        and node.value == 10000
        for node in ast.walk(tree)
    ), "Error: the script does not specify the required 10,000 simulations."

    random_calls = {
        "choice", "choices", "randint", "randrange", "integers", "multinomial",
        "uniform", "random", "rand", "randn", "sample", "randbelow"
    }
    called = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute):
                called.append(node.func.attr)
            elif isinstance(node.func, ast.Name):
                called.append(node.func.id)
    assert any(name in random_calls for name in called), \
        "Error: the script does not call a random-number API for the Monte Carlo walks."


def run_script():
    for path in (JSON_PATH, PLOT_PATH):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    result = subprocess.run(
        ["python3", str(SCRIPT_PATH)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=240,
    )
    assert result.returncode == 0, (
        f"Error: executing {SCRIPT_PATH} failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_and_check_outputs(expected_n, mc_low, mc_high):
    # Preserve the original existence assertions.
    assert JSON_PATH.exists(), f"Error: {JSON_PATH} not found. Did you save the JSON file?"
    assert JSON_PATH.is_file(), f"Error: {JSON_PATH} is not a valid file."
    assert PLOT_PATH.exists(), f"Error: {PLOT_PATH} not found. Did you save the plot?"
    assert PLOT_PATH.is_file(), f"Error: {PLOT_PATH} is not a valid file."
    assert PLOT_PATH.stat().st_size > 0, f"Error: {PLOT_PATH} is empty."

    try:
        with JSON_PATH.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Error: {JSON_PATH} does not contain valid JSON: {exc}")

    for key in REQUIRED_KEYS:
        assert key in data, f"Error: Missing key '{key}' in {JSON_PATH}."

    analytical = expected_n - 1
    assert data["sequence_length"] == expected_n, (
        f"Error: Incorrect sequence_length. Expected {expected_n}, "
        f"got {data['sequence_length']}."
    )
    assert data["analytical_mean_squared_distance"] == analytical, (
        f"Error: Incorrect analytical_mean_squared_distance. Expected {analytical}, "
        f"got {data['analytical_mean_squared_distance']}."
    )

    mc_dist = data["mc_mean_squared_distance"]
    assert isinstance(mc_dist, (int, float)) and not isinstance(mc_dist, bool), \
        "Error: mc_mean_squared_distance must be a number."
    assert math.isfinite(mc_dist), "Error: mc_mean_squared_distance must be finite."
    assert mc_low <= mc_dist <= mc_high, (
        f"Error: mc_mean_squared_distance {mc_dist} is outside the expected "
        f"statistical range [{mc_low}, {mc_high}]."
    )

    reported_error = data["relative_error"]
    assert isinstance(reported_error, (int, float)) and not isinstance(reported_error, bool), \
        "Error: relative_error must be a number."
    assert math.isfinite(reported_error), "Error: relative_error must be finite."
    expected_error = abs(mc_dist - analytical) / float(analytical)
    assert abs(expected_error - reported_error) <= 1e-4, (
        f"Error: relative_error calculation is incorrect. Expected approx "
        f"{expected_error}, got {reported_error}."
    )

    # A nonempty file named .png is insufficient: decode it as an actual,
    # nontrivial PNG image suitable for a histogram.
    try:
        with Image.open(PLOT_PATH) as image:
            assert image.format == "PNG", "Error: the plot is not a PNG image."
            image.verify()
        with Image.open(PLOT_PATH) as image:
            assert image.width >= 200 and image.height >= 150, \
                "Error: the histogram image is implausibly small."
            sample = image.convert("RGB")
            sample.thumbnail((128, 128))
            colors = sample.getcolors(maxcolors=128 * 128 + 1)
            assert colors is not None and len(colors) >= 3, \
                "Error: the PNG appears blank rather than containing a histogram."
    except (OSError, SyntaxError) as exc:
        raise AssertionError(f"Error: {PLOT_PATH} is not a valid PNG image: {exc}")


def test_analysis_artifact_and_outputs():
    check_script()
    original_fasta = FASTA_PATH.read_bytes()

    # Exercise the submitted program on a verifier-chosen sequence so answers
    # cannot be hardcoded for the shipped 110-residue FASTA.
    hidden_n = 41 + secrets.randbelow(33)
    alphabet = "ACDEFGHIKLMNPQRSTVWY"
    hidden_sequence = "".join(secrets.choice(alphabet) for _ in range(hidden_n))
    try:
        FASTA_PATH.write_text(
            ">verifier_hidden_sequence\n" +
            "\n".join(hidden_sequence[i:i + 17] for i in range(0, hidden_n, 17)) +
            "\n",
            encoding="ascii",
        )
        run_script()
        hidden_steps = hidden_n - 1
        load_and_check_outputs(
            hidden_n,
            hidden_steps * 0.75,
            hidden_steps * 1.25,
        )
    finally:
        FASTA_PATH.write_bytes(original_fasta)

    # Execute again on the requested input and retain the original verifier's
    # exact sequence, analytical, statistical-range, and error assertions.
    run_script()
    load_and_check_outputs(110, 95, 125)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
