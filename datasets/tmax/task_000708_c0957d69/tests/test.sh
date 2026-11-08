#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import uuid

import numpy as np
import pandas as pd
from PIL import Image, ImageDraw


def test_script_exists_and_executable():
    script_path = "/home/user/analyze.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_adversarial_corpus():
    script_path = "/home/user/analyze.sh"
    clean_base = "/opt/corpus/clean"
    evil_base = "/opt/corpus/evil"

    clean_dirs = [os.path.join(clean_base, d) for d in os.listdir(clean_base) if os.path.isdir(os.path.join(clean_base, d))]
    evil_dirs = [os.path.join(evil_base, d) for d in os.listdir(evil_base) if os.path.isdir(os.path.join(evil_base, d))]

    assert len(clean_dirs) > 0, f"No subdirectories found in {clean_base}"
    assert len(evil_dirs) > 0, f"No subdirectories found in {evil_base}"

    clean_failures = []
    evil_failures = []

    for d in clean_dirs:
        result = subprocess.run([script_path, d], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(d))

    for d in evil_dirs:
        result = subprocess.run([script_path, d], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(d))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_dirs)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_dirs)} evil bypassed: {', '.join(evil_failures)}")

    assert not error_messages, " | ".join(error_messages)


def _write_specs(threshold):
    img = Image.new("RGB", (600, 100), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)
    draw.text((10, 40), f"MINIMUM ACCEPTABLE CORRELATION: {threshold:.2f}", fill=(0, 0, 0))
    img.save("/app/specs.png")


def _write_joined_case(directory, target_corr, rng):
    count = 64
    x = np.linspace(-2.5, 2.5, count)
    x = x - x.mean()

    z = rng.normal(size=count)
    z = z - z.mean()
    z = z - x * (np.dot(z, x) / np.dot(x, x))
    z = z * (np.linalg.norm(x) / np.linalg.norm(z))
    y = target_corr * x + np.sqrt(1.0 - target_corr ** 2) * z

    ids = np.arange(10001, 10001 + count)
    table1 = pd.DataFrame({"user_id": ids, "metric_x": x})
    table2 = pd.DataFrame({"user_id": ids, "metric_y": y})

    # Unmatched extreme rows ensure the calculation is over the inner join.
    table1 = pd.concat([
        table1,
        pd.DataFrame({"user_id": [910001, 910002], "metric_x": [1.0e8, -1.0e8]}),
    ], ignore_index=True)
    table2 = pd.concat([
        table2,
        pd.DataFrame({"user_id": [920001, 920002], "metric_y": [-1.0e8, 1.0e8]}),
    ], ignore_index=True)

    table1 = table1.iloc[rng.permutation(len(table1))].reset_index(drop=True)
    table2 = table2.iloc[rng.permutation(len(table2))].reset_index(drop=True)
    table1.to_csv(os.path.join(directory, "table1.csv"), index=False)
    table2.to_csv(os.path.join(directory, "table2.csv"), index=False)


def test_opaque_generated_datasets_and_image_threshold():
    script_path = "/home/user/analyze.sh"
    specs_path = "/app/specs.png"
    with open(specs_path, "rb") as f:
        original_specs = f.read()

    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    scenarios = [(0.61, 0.56), (0.61, 0.68), (0.89, 0.84), (0.89, 0.95)]
    rng.shuffle(scenarios)

    try:
        with tempfile.TemporaryDirectory(prefix=f"case-{uuid.uuid4().hex}-") as root:
            for threshold, target_corr in scenarios:
                _write_specs(threshold)
                case_dir = os.path.join(root, uuid.uuid4().hex)
                os.makedirs(case_dir)
                _write_joined_case(case_dir, target_corr, rng)

                left = pd.read_csv(os.path.join(case_dir, "table1.csv"))
                right = pd.read_csv(os.path.join(case_dir, "table2.csv"))
                joined = left.merge(right, on="user_id", how="inner")
                actual_corr = joined["metric_x"].corr(joined["metric_y"])
                expected_status = 1 if actual_corr < threshold else 0

                result = subprocess.run(
                    [script_path, case_dir],
                    capture_output=True,
                    timeout=30,
                )
                assert result.returncode == expected_status, (
                    f"Wrong result for opaque generated input: correlation={actual_corr}, "
                    f"threshold={threshold}, expected exit {expected_status}, "
                    f"got {result.returncode}. stderr={result.stderr.decode(errors='replace')}"
                )
    finally:
        with open(specs_path, "wb") as f:
            f.write(original_specs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
