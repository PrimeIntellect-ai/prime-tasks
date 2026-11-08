#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFont
from sklearn.metrics import mean_squared_error

PIPELINE = "/home/user/pipeline.py"
OUTPUT = "/home/user/scored_pipeline_output.csv"
INPUT = "/app/data/batch_001.csv"
SPEC = "/app/legacy_model_spec.png"


def run_pipeline():
    assert os.path.isfile(PIPELINE), f"Expected pipeline script {PIPELINE} is missing."
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["python3", PIPELINE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} is missing."


def check_output(df_true, threshold=0.0001):
    df_true = df_true[["id", "score"]].sort_values("id").reset_index(drop=True)

    try:
        df_pred = pd.read_csv(OUTPUT)
    except Exception as e:
        assert False, f"Failed to read {OUTPUT} as CSV: {e}"

    assert 'id' in df_pred.columns and 'score' in df_pred.columns, "Output CSV must contain exactly 'id' and 'score' columns."
    assert len(df_pred.columns) == 2, f"Output CSV must contain exactly two columns, found {len(df_pred.columns)}."

    df_pred = df_pred.sort_values('id').reset_index(drop=True)
    assert len(df_true) == len(df_pred), f"Row count mismatch. Expected {len(df_true)}, got {len(df_pred)}."

    mse = mean_squared_error(df_true['score'], df_pred['score'])
    assert mse <= threshold, f"MSE threshold failed. Expected MSE <= {threshold}, got {mse}"


def make_spec(equation):
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    font = ImageFont.truetype(font_path, 24)
    text = "MODEL EQUATION: " + equation
    probe = Image.new("RGB", (1, 1), "white")
    bbox = ImageDraw.Draw(probe).textbbox((0, 0), text, font=font)
    image = Image.new("RGB", (bbox[2] - bbox[0] + 100, 200), "white")
    ImageDraw.Draw(image).text((50, 75), text, fill="black", font=font)
    image.save(SPEC)


def test_scored_pipeline_output():
    assert os.path.isfile(INPUT), f"Expected input file {INPUT} is missing."
    assert os.path.isfile(SPEC), f"Expected model specification image {SPEC} is missing."

    # Execute and validate the required pipeline against the original artifacts.
    run_pipeline()
    df_true = pd.read_csv(INPUT)
    df_true['score'] = 3.14 * df_true['feature_A'] - 1.618 * df_true['feature_B'] + 2.718 * df_true['feature_C'] + 42.0
    check_output(df_true)

    original_input = open(INPUT, "rb").read()
    original_spec = open(SPEC, "rb").read()
    original_output = open(OUTPUT, "rb").read()

    try:
        # Replace both artifacts with an unseen but identically structured job.
        # A hardcoded one-off calculation cannot pass this second execution.
        rng = secrets.SystemRandom()
        a = rng.choice([1.125, 2.375, 4.625, 5.875, 7.125])
        b = rng.choice([0.875, 2.125, 3.375, 4.875, 6.125])
        c = rng.choice([1.375, 3.125, 4.375, 5.625, 7.375])
        d = rng.choice([11.0, 27.0, 53.0, 68.0, 91.0])
        make_spec(f"score = {a} * feature_A - {b} * feature_B + {c} * feature_C + {d}")

        data_rng = np.random.default_rng(rng.randrange(1, 2**32))
        dynamic = pd.DataFrame({
            "id": data_rng.permutation(np.arange(2001, 2054)),
            "feature_A": data_rng.uniform(-20, 20, 53),
            "feature_B": data_rng.uniform(-5, 120, 53),
            "feature_C": data_rng.normal(3, 4, 53),
        })
        dynamic.to_csv(INPUT, index=False)

        run_pipeline()
        dynamic['score'] = a * dynamic['feature_A'] - b * dynamic['feature_B'] + c * dynamic['feature_C'] + d
        check_output(dynamic)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        with open(SPEC, "wb") as f:
            f.write(original_spec)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
