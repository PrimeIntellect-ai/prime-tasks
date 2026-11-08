#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import stat
import pytest

def test_clean_evidence_exists_and_permissions():
    """Test that the clean evidence log exists and has 600 permissions."""
    clean_log_path = "/app/clean_evidence.log"
    assert os.path.isfile(clean_log_path), f"Missing sanitized output file at {clean_log_path}"

    file_stat = os.stat(clean_log_path)
    permissions = oct(file_stat.st_mode)[-3:]
    assert permissions == "600", f"Expected file permissions 600, but got {permissions}"

def test_f1_score_redaction():
    """
    Test the F1 score of the PII redaction by comparing the sanitized output
    against the ground truth log. Target F1 >= 0.98.
    """
    gt_log_path = "/tests/ground_truth.log"
    clean_log_path = "/app/clean_evidence.log"

    assert os.path.isfile(gt_log_path), f"Ground truth file missing at {gt_log_path}"
    assert os.path.isfile(clean_log_path), f"Clean evidence file missing at {clean_log_path}"

    with open(gt_log_path, "r", encoding="utf-8", errors="replace") as f:
        gt_text = f.read()

    with open(clean_log_path, "r", encoding="utf-8", errors="replace") as f:
        actual_text = f.read()

    assert len(gt_text) == len(actual_text), (
        f"Length mismatch: Ground truth is {len(gt_text)} chars, "
        f"but clean evidence is {len(actual_text)} chars."
    )

    # Identify ground truth redaction indices
    gt_indices = set()
    ssn_pattern = re.compile(r'\b\d{3}-\d{2}-\d{4}\b')
    cc_pattern = re.compile(r'\b\d{4}-\d{4}-\d{4}-\d{4}\b|\b\d{16}\b')

    for match in ssn_pattern.finditer(gt_text):
        gt_indices.update(range(match.start(), match.end()))
    for match in cc_pattern.finditer(gt_text):
        gt_indices.update(range(match.start(), match.end()))

    # Identify actual redaction indices
    actual_indices = set()
    for i, (g, a) in enumerate(zip(gt_text, actual_text)):
        if a != g:
            if a == 'X':
                actual_indices.add(i)
        else:
            # If the character was already 'X' in the ground truth and is part of a PII,
            # we count it as a redaction attempt (since it matches the mask).
            if a == 'X' and i in gt_indices:
                actual_indices.add(i)

    tp = len(gt_indices & actual_indices)
    fp = len(actual_indices - gt_indices)
    fn = len(gt_indices - actual_indices)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0

    assert f1 >= 0.98, (
        f"Redaction F1 Score {f1:.4f} is below the threshold of 0.98. "
        f"(Precision: {precision:.4f}, Recall: {recall:.4f}, TP: {tp}, FP: {fp}, FN: {fn})"
    )

def test_cpp_source_exists():
    """Test that the student created the redactor.cpp source file."""
    cpp_path = "/home/user/redactor.cpp"
    assert os.path.isfile(cpp_path), f"Missing C++ source file at {cpp_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
