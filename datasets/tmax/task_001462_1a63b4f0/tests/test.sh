#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest
from PIL import Image, ImageStat

PLOT_SCRIPT = "/home/user/plot_results.py"
PLOT_ARTIFACT = "/home/user/artifact_plot.png"
FILTER_SCRIPT = "/home/user/filter_logs.py"
MIN_SIMILARITY_SCORE = 0.750


def run_filter(path):
    return subprocess.run(
        ["python3", FILTER_SCRIPT, path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_plot_artifact_exists():
    """Execute the plotting script headlessly and verify it creates a real, nonblank PNG."""
    assert os.path.isfile(PLOT_SCRIPT), f"Plotting script is missing at {PLOT_SCRIPT}."

    if os.path.exists(PLOT_ARTIFACT):
        os.remove(PLOT_ARTIFACT)

    env = os.environ.copy()
    env.pop("DISPLAY", None)
    result = subprocess.run(
        ["python3", PLOT_SCRIPT],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Plotting script failed in a headless environment with exit code "
        f"{result.returncode}. stdout={result.stdout!r} stderr={result.stderr!r}"
    )

    assert os.path.isfile(PLOT_ARTIFACT), (
        f"Plot artifact is missing at {PLOT_ARTIFACT}. Did the plotting script run successfully?"
    )
    assert os.path.getsize(PLOT_ARTIFACT) > 0, f"Plot artifact at {PLOT_ARTIFACT} is empty."

    try:
        with Image.open(PLOT_ARTIFACT) as image:
            assert image.format == "PNG", "Plot artifact is not a PNG image."
            image.verify()
        with Image.open(PLOT_ARTIFACT) as image:
            image.load()
            assert image.width >= 100 and image.height >= 100, "Plot image is implausibly small."
            extrema = ImageStat.Stat(image.convert("RGB")).extrema
            assert any(low != high for low, high in extrema), "Plot image is blank/uniform."
    except (OSError, SyntaxError) as exc:
        pytest.fail(f"Plot artifact is not a valid decodable image: {exc}")


def test_filter_logs_script_exists():
    """Verify that the log filtering script exists."""
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script is missing at {FILTER_SCRIPT}."


def test_adversarial_corpus_filtering():
    """Retain checks against the provided clean and evil corpora."""
    assert os.path.isfile(FILTER_SCRIPT), f"Cannot test filtering: {FILTER_SCRIPT} does not exist."

    clean_files = glob.glob("/app/logs/clean/*.json")
    evil_files = glob.glob("/app/logs/evil/*.json")

    assert len(clean_files) > 0, "No clean log files found to test."
    assert len(evil_files) > 0, "No evil log files found to test."

    clean_failures = []
    for clean_file in clean_files:
        result = run_filter(clean_file)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(clean_file))

    evil_failures = []
    for evil_file in evil_files:
        result = run_filter(evil_file)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(evil_file))

    error_messages = []
    if evil_failures:
        error_messages.append(
            f"{len(evil_failures)} of {len(evil_files)} evil logs did not exit 1: "
            f"{', '.join(evil_failures)}"
        )
    if clean_failures:
        error_messages.append(
            f"{len(clean_failures)} of {len(clean_files)} clean logs were rejected: "
            f"{', '.join(clean_failures)}"
        )
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_generated_hidden_corpus():
    """Exercise the stated rules on randomized filenames and values."""
    assert os.path.isfile(FILTER_SCRIPT), f"Cannot test filtering: {FILTER_SCRIPT} does not exist."
    rng = random.SystemRandom()
    cases = []

    # Exact inclusive boundaries and equality cases.
    cases.extend([
        ({"p_value": 0.0, "ci_lower": -2.0, "ci_upper": -2.0, "similarity_score": MIN_SIMILARITY_SCORE}, 0),
        ({"p_value": 1.0, "ci_lower": 4.0, "ci_upper": 4.0, "similarity_score": MIN_SIMILARITY_SCORE}, 0),
        ({"p_value": -0.000001, "ci_lower": 0.0, "ci_upper": 1.0, "similarity_score": 0.95}, 1),
        ({"p_value": 1.000001, "ci_lower": 0.0, "ci_upper": 1.0, "similarity_score": 0.95}, 1),
        ({"p_value": 0.5, "ci_lower": 1.000001, "ci_upper": 1.0, "similarity_score": 0.95}, 1),
        ({"p_value": 0.5, "ci_lower": -1.0, "ci_upper": 1.0, "similarity_score": MIN_SIMILARITY_SCORE - 0.000001}, 1),
    ])

    for _ in range(24):
        lower = rng.uniform(-5.0, 4.0)
        upper = lower + rng.uniform(0.0, 5.0)
        cases.append(({
            "p_value": rng.uniform(0.0, 1.0),
            "ci_lower": lower,
            "ci_upper": upper,
            "similarity_score": rng.uniform(MIN_SIMILARITY_SCORE, 1.5),
        }, 0))

    for _ in range(12):
        cases.append(({
            "p_value": rng.choice([rng.uniform(-2.0, -0.00001), rng.uniform(1.00001, 3.0)]),
            "ci_lower": rng.uniform(-2.0, 0.0),
            "ci_upper": rng.uniform(0.0, 2.0),
            "similarity_score": rng.uniform(MIN_SIMILARITY_SCORE, 1.5),
        }, 1))

    for _ in range(12):
        upper = rng.uniform(-3.0, 3.0)
        cases.append(({
            "p_value": rng.uniform(0.0, 1.0),
            "ci_lower": upper + rng.uniform(0.00001, 3.0),
            "ci_upper": upper,
            "similarity_score": rng.uniform(MIN_SIMILARITY_SCORE, 1.5),
        }, 1))

    for _ in range(12):
        lower = rng.uniform(-3.0, 2.0)
        cases.append(({
            "p_value": rng.uniform(0.0, 1.0),
            "ci_lower": lower,
            "ci_upper": lower + rng.uniform(0.0, 3.0),
            "similarity_score": rng.uniform(-1.0, MIN_SIMILARITY_SCORE - 0.00001),
        }, 1))

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="logcheck_") as directory:
        for values, expected in cases:
            values["run_id"] = "exp_" + secrets.token_hex(10)
            path = os.path.join(directory, secrets.token_hex(16) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(values, handle)
            result = run_filter(path)
            if result.returncode != expected:
                failures.append(
                    f"input={values!r}, expected exit {expected}, got {result.returncode}, "
                    f"stderr={result.stderr!r}"
                )

    assert not failures, "Generated corpus failures:\n" + "\n".join(failures[:10])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
