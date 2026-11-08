#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import subprocess
import sys

import pandas as pd
import pytest


def derive_truth():
    data_dir = "/home/user/audit_data"
    rows = []

    for filename in sorted(os.listdir(data_dir)):
        path = os.path.join(data_dir, filename)
        if not os.path.isfile(path):
            continue

        data = open(path, "rb").read()
        is_malicious = 0

        if len(data) >= 23 and data[:5] == b"AUDIT":
            expected_md5 = data[5:21]
            payload = bytes(byte ^ 0x5A for byte in data[21:])

            if hashlib.md5(payload).digest() == expected_md5 and len(payload) >= 2:
                filename_length = int.from_bytes(payload[:2], "little")
                if 2 + filename_length <= len(payload):
                    target = payload[2:2 + filename_length]
                    if target.startswith(b"/") or b"../" in target:
                        is_malicious = 1

        rows.append({"filename": filename, "is_malicious": is_malicious})

    return pd.DataFrame(rows)


def test_report_accuracy():
    script_path = "/home/user/analyze.py"
    report_path = "/home/user/report.csv"

    assert os.path.exists(script_path), f"Analysis script not found at {script_path}"
    assert os.path.isfile(script_path), f"{script_path} is not a file"

    if os.path.lexists(report_path):
        os.remove(report_path)

    try:
        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Analysis script timed out")

    assert result.returncode == 0, (
        f"Analysis script exited with status {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.exists(report_path), f"Report file not found at {report_path}"
    assert os.path.isfile(report_path), f"{report_path} is not a file"

    try:
        pred = pd.read_csv(report_path)
    except Exception as e:
        pytest.fail(f"Failed to read {report_path} as CSV: {e}")

    truth = derive_truth()

    assert 'filename' in pred.columns, f"'filename' column missing in {report_path}"
    assert 'is_malicious' in pred.columns, f"'is_malicious' column missing in {report_path}"
    assert list(pred.columns) == ['filename', 'is_malicious'], (
        f"{report_path} must contain exactly the columns filename,is_malicious"
    )
    assert not pred['filename'].duplicated().any(), "Report contains duplicate filenames"
    assert set(pred['filename']) == set(truth['filename']), (
        "Report must contain exactly one row for every audit payload"
    )
    assert pred['is_malicious'].isin([0, 1]).all(), (
        "is_malicious values must be 0 or 1"
    )

    merged = pd.merge(truth, pred, on='filename', suffixes=('_truth', '_pred'))

    assert len(merged) > 0, "No matching filenames found between the report and ground truth"

    correct = (merged['is_malicious_truth'] == merged['is_malicious_pred']).sum()
    accuracy = correct / len(truth)

    threshold = 0.95
    assert accuracy >= threshold, f"Accuracy {accuracy:.4f} is below the required threshold of {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
