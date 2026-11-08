#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import numpy as np
import pandas as pd
from scipy.stats import ks_2samp

RESULT = "/home/user/analysis_result.json"
REFERENCE = "/home/user/reference.csv"
SIGNAL = "/home/user/signal.csv"


def load_result():
    with open(RESULT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, "analysis_result.json is not a valid JSON file."


def expected_from_inputs():
    ref = pd.read_csv(REFERENCE)
    signal = pd.read_csv(SIGNAL)
    ref_rows = list(ref[["base", "mean_current", "std_dev"]].itertuples(index=False, name=None))

    observed_means = []
    predicted = []
    event_ids = sorted(signal["event_id"].unique(), key=lambda x: float(x))
    for event_id in event_ids:
        values = [float(x) for x in signal.loc[signal["event_id"] == event_id, "current_val"]]
        values.remove(max(values))
        values.remove(min(values))
        observed = float(np.mean(values))
        observed_means.append(observed)
        predicted.append(min(ref_rows, key=lambda row: abs(float(row[1]) - observed))[0])

    ref_by_base = {row[0]: (float(row[1]), float(row[2])) for row in ref_rows}
    np.random.seed(42)
    samples = []
    for base in predicted:
        mean, std = ref_by_base[base]
        samples.extend(np.random.normal(mean, std, 100))
    pvalue = round(float(ks_2samp(observed_means, samples).pvalue), 4)
    return "-".join(predicted), pvalue


def assert_result_matches(expected_sequence, expected_pvalue, tolerance=0.00005):
    assert os.path.isfile(RESULT), f"Expected output file is missing: {RESULT}"
    data = load_result()
    assert "sequence" in data, "The key 'sequence' is missing from the JSON output."
    assert "ks_pvalue" in data, "The key 'ks_pvalue' is missing from the JSON output."
    assert data["sequence"] == expected_sequence, (
        f"Sequence mismatch. Expected '{expected_sequence}', but got '{data['sequence']}'."
    )
    assert isinstance(data["ks_pvalue"], (int, float)), "ks_pvalue must be a number."
    assert math.isclose(data["ks_pvalue"], expected_pvalue, abs_tol=tolerance), (
        f"KS p-value mismatch. Expected approximately {expected_pvalue}, "
        f"but got {data['ks_pvalue']}."
    )


def discover_python_scripts():
    scripts = []
    skipped_dirs = {".cache", "__pycache__", ".venv", "venv", "site-packages"}
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in skipped_dirs]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".py"):
                scripts.append(path)
                continue
            try:
                with open(path, "rb") as f:
                    first_line = f.readline(200).lower()
                if first_line.startswith(b"#!") and b"python" in first_line:
                    scripts.append(path)
            except OSError:
                pass
    return sorted(set(scripts))


def make_case(ref_rows, assignments):
    ref = pd.DataFrame(ref_rows, columns=["base", "mean_current", "std_dev"])
    means = dict(zip(ref["base"], ref["mean_current"]))
    rows = []
    for index, (event_id, base, offset) in enumerate(assignments):
        center = float(means[base]) + offset
        values = [center - 0.4, center - 0.1, center, center + 0.2, center + 0.3,
                  center - 12.0, center + 12.0]
        if index == 0:
            values.append(center + 12.0)  # Verify that only one duplicate maximum is removed.
        for value in reversed(values):
            rows.append({"event_id": event_id, "current_val": value})
    return ref, pd.DataFrame(list(reversed(rows)))


def test_analysis_result_exists():
    assert os.path.isfile(RESULT), f"Expected output file is missing: {RESULT}"


def test_analysis_result_format_and_content():
    data = load_result()
    assert "sequence" in data, "The key 'sequence' is missing from the JSON output."
    assert "ks_pvalue" in data, "The key 'ks_pvalue' is missing from the JSON output."

    expected_sequence = "A-G-C-T-A-A-T-G-C-C"
    assert data["sequence"] == expected_sequence, (
        f"Sequence mismatch. Expected '{expected_sequence}', but got '{data['sequence']}'."
    )

    expected_pvalue = 0.8166
    assert isinstance(data["ks_pvalue"], (int, float)), "ks_pvalue must be a number."
    assert math.isclose(data["ks_pvalue"], expected_pvalue, abs_tol=0.0005), (
        f"KS p-value mismatch. Expected approximately {expected_pvalue}, "
        f"but got {data['ks_pvalue']}. Ensure you used the correct seed, filtering logic, and statistical test."
    )

    recomputed_sequence, recomputed_pvalue = expected_from_inputs()
    assert_result_matches(recomputed_sequence, recomputed_pvalue)


def test_submitted_script_recomputes_from_csv_inputs():
    scripts = discover_python_scripts()
    assert scripts, "No Python analysis script was found under /home/user."

    original_reference = open(REFERENCE, "rb").read()
    original_signal = open(SIGNAL, "rb").read()
    original_result = open(RESULT, "rb").read() if os.path.exists(RESULT) else None

    case1 = make_case(
        [("G", 29.0, 1.7), ("A", 2.0, 0.8), ("T", 47.0, 2.1), ("C", 14.0, 1.2)],
        [(31, "T", 0.4), (2, "C", -0.3), (18, "A", 0.2), (7, "G", -0.5),
         (45, "C", 0.1), (12, "T", -0.2), (28, "A", 0.5), (4, "G", 0.3),
         (39, "T", -0.4), (15, "C", 0.2), (23, "G", -0.1), (9, "A", -0.2)],
    )
    case2 = make_case(
        [("T", -18.0, 0.9), ("C", 63.0, 2.4), ("A", 108.0, 1.3), ("G", 7.0, 1.8)],
        [(50, "A", -0.4), (1, "T", 0.2), (22, "G", 0.4), (6, "C", -0.3),
         (35, "T", -0.1), (9, "A", 0.3), (17, "C", 0.1), (3, "G", -0.2)],
    )

    errors = []
    passing_script = None
    try:
        for script in scripts:
            try:
                test_cases = [(None, None), case1, case2]
                for ref_frame, signal_frame in test_cases:
                    if ref_frame is None:
                        open(REFERENCE, "wb").write(original_reference)
                        open(SIGNAL, "wb").write(original_signal)
                    else:
                        ref_frame.to_csv(REFERENCE, index=False)
                        signal_frame.to_csv(SIGNAL, index=False)

                    if os.path.exists(RESULT):
                        os.remove(RESULT)
                    expected_sequence, expected_pvalue = expected_from_inputs()
                    proc = subprocess.run(
                        ["python3", script], cwd="/home/user", text=True,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
                    )
                    assert proc.returncode == 0, proc.stderr[-1000:]
                    assert_result_matches(expected_sequence, expected_pvalue)
                passing_script = script
                break
            except Exception as exc:
                errors.append(f"{script}: {exc}")

        assert passing_script is not None, (
            "No submitted Python script correctly recomputed the analysis for the supplied and verification inputs. "
            + " | ".join(errors[-5:])
        )
    finally:
        open(REFERENCE, "wb").write(original_reference)
        open(SIGNAL, "wb").write(original_signal)
        if original_result is None:
            if os.path.exists(RESULT):
                os.remove(RESULT)
        else:
            open(RESULT, "wb").write(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
