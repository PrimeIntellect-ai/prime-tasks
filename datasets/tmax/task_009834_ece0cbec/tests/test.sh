#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

import numpy as np

SCRIPT_PATH = "/home/user/compare_models.sh"
REPORT_PATH = "/home/user/report.txt"
REF_PATH = "/home/user/ref_latency.txt"
TEST_PATH = "/home/user/test_latency.txt"


def expected_report(ref_data, test_data):
    ref_data = np.atleast_1d(np.asarray(ref_data, dtype=float))
    test_data = np.atleast_1d(np.asarray(test_data, dtype=float))

    ref_mean = np.mean(ref_data)
    ref_std = np.std(ref_data, ddof=1)
    test_mean = np.mean(test_data)
    test_std = np.std(test_data, ddof=1)

    np.random.seed(42)
    diffs = []
    for _ in range(5000):
        b_test = np.random.choice(test_data, size=len(test_data), replace=True)
        b_ref = np.random.choice(ref_data, size=len(ref_data), replace=True)
        diffs.append(np.mean(b_test) - np.mean(b_ref))

    ci_lower = np.percentile(diffs, 2.5)
    ci_upper = np.percentile(diffs, 97.5)

    if ci_upper < 0.00:
        conclusion = "IMPROVED"
    elif ci_lower > 0.00:
        conclusion = "DEGRADED"
    else:
        conclusion = "UNCHANGED"

    return (
        f"Ref: Mean={ref_mean:.2f}, Std={ref_std:.2f}\n"
        f"Test: Mean={test_mean:.2f}, Std={test_std:.2f}\n"
        f"CI: [{ci_lower:.2f}, {ci_upper:.2f}]\n"
        f"Conclusion: {conclusion}"
    )


def run_script(ref_path, test_path):
    result = subprocess.run(
        ["bash", SCRIPT_PATH, str(ref_path), str(test_path)],
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    return result.stdout.strip()


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), (
        f"Bash script not found at expected absolute path: {SCRIPT_PATH}"
    )
    syntax = subprocess.run(
        ["bash", "-n", SCRIPT_PATH], capture_output=True, text=True
    )
    assert syntax.returncode == 0, f"Invalid Bash syntax:\n{syntax.stderr}"


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), (
        f"Deliverable report not found at expected absolute path: {REPORT_PATH}"
    )


def test_report_content_and_original_execution():
    assert os.path.isfile(REPORT_PATH), (
        f"Deliverable report not found at expected absolute path: {REPORT_PATH}"
    )
    with open(REPORT_PATH, "r") as f:
        actual_report = f.read().strip()

    # Preserve the original deterministic assertion against the setup dataset.
    np.random.seed(123)
    ref_data = np.random.normal(loc=50.0, scale=5.0, size=500)
    test_data = np.random.normal(loc=48.0, scale=4.5, size=500)
    expected = expected_report(ref_data, test_data)

    assert actual_report == expected, (
        f"The content of {REPORT_PATH} does not match the expected output.\n"
        f"--- Expected ---\n{expected}\n"
        f"--- Got ---\n{actual_report}"
    )

    executed = run_script(REF_PATH, TEST_PATH)
    assert executed == expected, (
        "Executing compare_models.sh on the required input files did not produce "
        f"the expected report.\n--- Expected ---\n{expected}\n"
        f"--- Got ---\n{executed}"
    )


def test_script_uses_supplied_positional_files(tmp_path):
    # Generate verifier-time data so a hardcoded report or script cannot pass.
    nonce = int.from_bytes(os.urandom(4), "big")
    jitter = (nonce % 1000) / 10000.0
    ref_values = np.array([
        19.15 + jitter, 20.22, 18.91, 21.07, 20.48, 19.76,
        20.03, 21.31, 18.67, 20.89, 19.44, 20.61, 19.98,
    ])
    test_values = np.array([
        25.24, 24.71 + jitter, 26.03, 25.58, 24.92, 26.37,
        25.11, 24.48, 25.83, 26.12, 24.66, 25.39, 25.72,
        24.95, 26.21,
    ])

    ref_file = tmp_path / "dynamic_reference.dat"
    test_file = tmp_path / "dynamic_test.dat"
    ref_file.write_text("".join(f"{x:.8f}\n" for x in ref_values))
    test_file.write_text("".join(f"{x:.8f}\n" for x in test_values))

    # Derive answers from the exact bytes supplied to the submitted script.
    ref_loaded = np.loadtxt(ref_file)
    test_loaded = np.loadtxt(test_file)

    expected_forward = expected_report(ref_loaded, test_loaded)
    actual_forward = run_script(ref_file, test_file)
    assert actual_forward == expected_forward, (
        "Script did not correctly process its supplied positional files.\n"
        f"--- Expected ---\n{expected_forward}\n"
        f"--- Got ---\n{actual_forward}"
    )

    expected_swapped = expected_report(test_loaded, ref_loaded)
    actual_swapped = run_script(test_file, ref_file)
    assert actual_swapped == expected_swapped, (
        "Script did not respect the reference/test positional argument order.\n"
        f"--- Expected ---\n{expected_swapped}\n"
        f"--- Got ---\n{actual_swapped}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
