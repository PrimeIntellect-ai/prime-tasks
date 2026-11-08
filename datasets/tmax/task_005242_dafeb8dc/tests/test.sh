#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import pytest

def test_subtitles_accuracy():
    """Check if the generated subtitles meet the accuracy threshold against the ground truth."""
    output_file = '/home/user/es_subtitles.json'
    assert os.path.exists(output_file), f"Output file not found: {output_file}"

    try:
        with open(output_file, 'r') as f:
            agent_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse JSON from {output_file}")

    # Ground truth mapping based on the provided metric snippet
    ground_truth = {
        "0": "Bienvenido",
        "1": "Bienvenido",
        "2": "Ajustes",
        "3": "Ajustes",
        "4": None,
        "5": "Guardar cambios"
    }

    correct = 0
    total = len(ground_truth)

    for k, v in ground_truth.items():
        if str(k) in agent_data and agent_data[str(k)] == v:
            correct += 1

    accuracy = correct / total
    assert accuracy >= 0.80, f"Accuracy {accuracy:.2f} is below the 0.80 threshold. Correct: {correct}/{total}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
