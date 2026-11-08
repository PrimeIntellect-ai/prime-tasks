#!/bin/bash
set -e
mkdir -p /logs/verifier

# The legacy oracle is available for investigation during the task, but must not
# be available to the replacement while it is being verified.
rm -f /app/drift_oracle

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess

import numpy as np
from PIL import Image


def test_plot_experiments_fixed():
    script_path = "/home/user/plot_experiments.py"
    plot_path = "/home/user/experiment_plot.png"

    assert os.path.isfile(script_path), f"Plot script {script_path} does not exist."
    os.remove(plot_path) if os.path.exists(plot_path) else None

    result = subprocess.run(
        ["python3", script_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"plot_experiments.py failed to run:\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )

    assert os.path.exists(plot_path), f"Plot file {plot_path} was not created."
    assert os.path.getsize(plot_path) > 100, (
        f"Plot file {plot_path} is suspiciously small or empty."
    )

    # Require a genuine, decodable, nonblank PNG rather than arbitrary bytes.
    with Image.open(plot_path) as image:
        assert image.format == "PNG", f"{plot_path} is not a PNG image."
        image.verify()

    with Image.open(plot_path) as image:
        image = image.convert("RGB")
        assert image.width >= 100 and image.height >= 100, (
            f"Plot dimensions are suspiciously small: {image.size}."
        )
        pixels = np.asarray(image)
        assert int(pixels.max()) > int(pixels.min()), "Rendered plot is blank."
        non_background = np.any(pixels < 245, axis=2)
        assert int(non_background.sum()) > 100, "Rendered plot contains no visible content."


def expected_drift(actual_vals, predicted_vals):
    total = 0.0
    for actual, predicted in zip(actual_vals, predicted_vals):
        diff = math.log(predicted + 1.0) - math.log(actual + 1.0)
        total += diff * diff
    return f"{math.sqrt(total / len(actual_vals)):.4f}"


def test_new_oracle_fuzz_equivalence():
    agent_script = "/home/user/new_oracle.py"
    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is not a regular file."

    random.seed(42)

    for i in range(100):
        length = random.randint(5, 100)
        actual_vals = [random.randint(0, 10000) for _ in range(length)]
        predicted_vals = [random.randint(0, 10000) for _ in range(length)]

        actual_csv = ",".join(map(str, actual_vals))
        predicted_csv = ",".join(map(str, predicted_vals))
        oracle_output = expected_drift(actual_vals, predicted_vals)

        agent_result = subprocess.run(
            ["python3", agent_script, actual_csv, predicted_csv],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert agent_result.returncode == 0, (
            f"Agent script failed on iteration {i}:\nSTDERR: {agent_result.stderr}"
        )
        agent_output = agent_result.stdout.strip()

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i}!\n"
            f"Input actual: {actual_csv[:50]}...\n"
            f"Input predicted: {predicted_csv[:50]}...\n"
            f"Oracle output: '{oracle_output}'\n"
            f"Agent output: '{agent_output}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
