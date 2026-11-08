#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import stat
import subprocess
from pathlib import Path


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_pipeline_script_content():
    script_path = "/home/user/run_pipeline.sh"
    with open(script_path, "r") as f:
        content = f.read()

    assert content.startswith("#!/bin/bash") or content.startswith("#!/usr/bin/env bash"), \
        "Script does not have a proper bash shebang."
    assert re.search(r"export\s+OPENBLAS_NUM_THREADS=2\b", content), \
        "Script does not correctly export OPENBLAS_NUM_THREADS=2."
    assert re.search(r"export\s+OMP_NUM_THREADS=2\b", content), \
        "Script does not correctly export OMP_NUM_THREADS=2."


def test_predictions_output():
    predictions_path = "/home/user/predictions.txt"
    assert os.path.isfile(predictions_path), f"Output file {predictions_path} does not exist. Did you run the script?"

    with open(predictions_path, "r") as f:
        content = f.read().strip()

    expected_content = "Inference results for feature_A: [2.0, 4.0, 6.0, 8.0, 10.0]"
    assert content == expected_content, \
        f"Content of {predictions_path} is incorrect. Expected: '{expected_content}', Got: '{content}'"


def test_pipeline_actually_runs_and_parses_absolute_correlations():
    pipeline = Path("/home/user/run_pipeline.sh")
    correlations = Path("/home/user/scripts/get_correlations.py")
    inference = Path("/home/user/scripts/run_inference.py")
    predictions = Path("/home/user/predictions.txt")
    dataset = "/home/user/data/dataset.csv"

    saved_corr = correlations.read_bytes()
    saved_corr_mode = stat.S_IMODE(correlations.stat().st_mode)
    saved_infer = inference.read_bytes()
    saved_infer_mode = stat.S_IMODE(inference.stat().st_mode)
    had_predictions = predictions.exists()
    saved_predictions = predictions.read_bytes() if had_predictions else None

    try:
        # Multiple runtime-selected winners prevent a fixed feature or fixed output
        # from satisfying the behavioral check.
        for trial in range(8):
            winner = secrets.choice(["feature_A", "feature_B", "feature_C"])
            token = "probe-" + secrets.token_hex(16)
            corr_marker = Path(f"/tmp/correlation-called-{token}")
            infer_marker = Path(f"/tmp/inference-called-{token}")

            values = {
                winner: -0.99,
                "feature_A": 0.17,
                "feature_B": 0.31,
                "feature_C": 0.43,
            }
            values[winner] = -0.99
            rows = list(values.items())
            random.SystemRandom().shuffle(rows)

            corr_source = f'''#!/usr/bin/env python3
import os
import sys
if sys.argv != [sys.argv[0], {dataset!r}]:
    sys.exit(41)
if os.environ.get("OPENBLAS_NUM_THREADS") != "2" or os.environ.get("OMP_NUM_THREADS") != "2":
    sys.exit(42)
open({str(corr_marker)!r}, "w").write("called")
for name, value in {rows!r}:
    print(f"{{name}}:{{value}}")
'''
            infer_source = f'''#!/usr/bin/env python3
import os
import sys
if sys.argv != [sys.argv[0], {dataset!r}, {winner!r}]:
    sys.exit(51)
if os.environ.get("OPENBLAS_NUM_THREADS") != "2" or os.environ.get("OMP_NUM_THREADS") != "2":
    sys.exit(52)
open({str(infer_marker)!r}, "w").write("called")
print({token!r})
'''
            correlations.write_text(corr_source)
            inference.write_text(infer_source)
            correlations.chmod(0o755)
            inference.chmod(0o755)
            predictions.unlink(missing_ok=True)

            env = os.environ.copy()
            env["OPENBLAS_NUM_THREADS"] = "9"
            env["OMP_NUM_THREADS"] = "9"
            result = subprocess.run(
                [str(pipeline)],
                cwd="/home/user",
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )

            assert result.returncode == 0, \
                f"Pipeline failed during behavioral test: {result.stderr}"
            assert corr_marker.is_file(), \
                "Pipeline did not execute get_correlations.py."
            assert infer_marker.is_file(), \
                "Pipeline did not execute run_inference.py with the feature having the highest absolute correlation."
            assert predictions.is_file(), \
                "Pipeline did not create /home/user/predictions.txt."
            assert predictions.read_text().strip() == token, \
                "Pipeline did not redirect run_inference.py standard output to predictions.txt."

            corr_marker.unlink(missing_ok=True)
            infer_marker.unlink(missing_ok=True)
    finally:
        correlations.write_bytes(saved_corr)
        correlations.chmod(saved_corr_mode)
        inference.write_bytes(saved_infer)
        inference.chmod(saved_infer_mode)
        if had_predictions:
            predictions.write_bytes(saved_predictions)
        else:
            predictions.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
