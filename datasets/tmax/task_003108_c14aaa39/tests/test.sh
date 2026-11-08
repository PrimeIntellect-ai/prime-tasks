#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

import numpy as np
from sklearn.decomposition import PCA

SCRIPT_PATH = "/home/user/validate_pipeline.py"
REPORT_PATH = "/home/user/report.txt"
RUN1_PATH = "/home/user/outputs_run1.csv"
RUN2_PATH = "/home/user/outputs_run2.csv"


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} was not found."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a valid file."


def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"The report file {REPORT_PATH} was not found."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a valid file."


def test_report_content():
    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()

    expected_trace = "0.6121"
    expected_corr = "0.9995"
    expected_line1 = f"Covariance Trace: {expected_trace}"
    expected_line2 = f"PC1 Correlation: {expected_corr}"

    assert expected_line1 in content, (
        f"Expected '{expected_line1}' to be in {REPORT_PATH}. Found:\n{content}"
    )
    assert expected_line2 in content, (
        f"Expected '{expected_line2}' to be in {REPORT_PATH}. Found:\n{content}"
    )

    lines = content.splitlines()
    assert len(lines) >= 2, f"Expected at least 2 lines in {REPORT_PATH}, found {len(lines)}"
    assert lines[0].strip() == expected_line1, (
        f"First line of report does not match exactly. Expected: '{expected_line1}', "
        f"Got: '{lines[0].strip()}'"
    )
    assert lines[1].strip() == expected_line2, (
        f"Second line of report does not match exactly. Expected: '{expected_line2}', "
        f"Got: '{lines[1].strip()}'"
    )


def _expected_report(run1, run2):
    pca = PCA(n_components=2, random_state=42)
    reduced1 = pca.fit_transform(run1)
    reduced2 = pca.transform(run2)
    covariance_trace = np.trace(np.cov(reduced1, rowvar=False))
    correlation = np.corrcoef(reduced1[:, 0], reduced2[:, 0])[0, 1]
    return (
        f"Covariance Trace: {covariance_trace:.4f}\n"
        f"PC1 Correlation: {correlation:.4f}"
    )


def test_script_executes_and_computes_from_inputs():
    backups = {}
    for path in (RUN1_PATH, RUN2_PATH, REPORT_PATH):
        with open(path, "rb") as f:
            backups[path] = f.read()

    try:
        for _ in range(2):
            rng = np.random.default_rng(secrets.randbits(128))
            scales = np.linspace(0.4, 2.5, 50)
            run1 = rng.normal(size=(100, 50)) * scales
            run2 = run1 * rng.uniform(0.85, 1.15, size=(1, 50))
            run2 += rng.normal(0, 0.03, size=(100, 50))
            expected = _expected_report(run1, run2)

            np.savetxt(RUN1_PATH, run1, delimiter=",")
            np.savetxt(RUN2_PATH, run2, delimiter=",")
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)

            result = subprocess.run(
                ["python3", SCRIPT_PATH],
                cwd="/home/user",
                text=True,
                capture_output=True,
                timeout=30,
            )
            assert result.returncode == 0, (
                f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert os.path.isfile(REPORT_PATH), (
                f"Executing {SCRIPT_PATH} did not create {REPORT_PATH}."
            )
            with open(REPORT_PATH, "r") as f:
                actual = f.read().strip()
            assert actual == expected, (
                "The executed script did not compute the expected PCA/correlation results "
                f"for the supplied datasets.\nExpected:\n{expected}\nActual:\n{actual}"
            )
    finally:
        for path, data in backups.items():
            with open(path, "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
