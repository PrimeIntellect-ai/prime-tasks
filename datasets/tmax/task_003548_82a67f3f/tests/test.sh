#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def flatten_manifest(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON from {filepath}: {e}")

    tuples = set()
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                # Attempt to identify the artifact name
                name = item.get("artifact_name", item.get("name"))
                if not name:
                    for v in item.values():
                        if isinstance(v, str) and '.tar.gz' in v:
                            name = v
                            break
                name = name or str(item)
                for k, v in item.items():
                    # Exclude the name key itself from the metadata tuples if it's explicitly 'artifact_name' or 'name'
                    if k in ("artifact_name", "name"):
                        continue
                    tuples.add((name, k, str(v).strip()))
    elif isinstance(data, dict):
        for k, v in data.items():
            if isinstance(v, dict):
                for sub_k, sub_v in v.items():
                    tuples.add((k, sub_k, str(sub_v).strip()))
            else:
                tuples.add(("root", k, str(v).strip()))
    return tuples

def test_manifest_accuracy():
    target_file = "/home/user/manifest.json"
    truth_file = "/tests/expected_manifest.json"

    assert os.path.isfile(target_file), f"Target manifest file not found at {target_file}"
    assert os.path.isfile(truth_file), f"Ground truth manifest file not found at {truth_file}"

    target_tuples = flatten_manifest(target_file)
    truth_tuples = flatten_manifest(truth_file)

    assert len(truth_tuples) > 0, "Ground truth manifest is empty or could not be flattened."

    matching_tuples = target_tuples.intersection(truth_tuples)
    accuracy = len(matching_tuples) / len(truth_tuples)

    threshold = 0.95
    assert accuracy >= threshold, (
        f"Metadata extraction accuracy is {accuracy:.4f} (Threshold: {threshold}). "
        f"Matched {len(matching_tuples)} out of {len(truth_tuples)} tuples."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
