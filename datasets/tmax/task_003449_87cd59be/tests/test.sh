#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import gzip
import json
import glob
import re
import pytest

def get_ground_truth():
    """
    Reconstruct the ground truth by finding all .md files > 1KB in /home/user/docs
    and extracting the first H1 heading (ATX style).
    """
    gt = {}
    md_files = glob.glob('/home/user/docs/**/*.md', recursive=True)
    for f in md_files:
        if os.path.getsize(f) > 1024:
            base_name = os.path.basename(f)
            with open(f, 'r', encoding='utf-8') as file:
                for line in file:
                    m = re.match(r'^#\s+(.*)', line)
                    if m:
                        gt[base_name] = m.group(1).strip()
                        break
    return gt

def test_metadata_extraction_f1_score():
    """
    Verify that the agent correctly extracted the headings and created the tar.gz archive.
    Calculates the F1 score of the extracted headings compared to the ground truth.
    """
    archive_path = '/home/user/docs_metadata.tar.gz'
    assert os.path.exists(archive_path), f"Archive {archive_path} does not exist"

    try:
        with tarfile.open(archive_path, 'r:gz') as tar:
            try:
                member = tar.getmember('metadata.json.gz')
            except KeyError:
                pytest.fail("metadata.json.gz not found inside the tar archive")

            with tar.extractfile(member) as f:
                with gzip.GzipFile(fileobj=f) as gz:
                    try:
                        data = json.load(gz)
                    except json.JSONDecodeError:
                        pytest.fail("metadata.json.gz does not contain valid JSON")
    except tarfile.ReadError:
        pytest.fail(f"{archive_path} is not a valid tar.gz archive")

    assert isinstance(data, list), "Extracted JSON data is not a list of objects"

    agent_dict = {}
    for item in data:
        assert 'filename' in item and 'heading' in item, "JSON objects must contain 'filename' and 'heading' keys"
        agent_dict[item['filename']] = item['heading']

    gt_dict = get_ground_truth()

    tp = sum(1 for k, v in agent_dict.items() if k in gt_dict and gt_dict[k] == v)
    fp = sum(1 for k, v in agent_dict.items() if k not in gt_dict or gt_dict[k] != v)
    fn = sum(1 for k in gt_dict if k not in agent_dict or gt_dict[k] != agent_dict[k])

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

    assert f1 >= 1.0, f"F1 Score is {f1:.4f}, expected >= 1.0. True Positives: {tp}, False Positives: {fp}, False Negatives: {fn}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
