#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import time
import pytest

def load_data(filepath):
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
        return set(frozenset(d.items()) for d in data)
    except Exception as e:
        return set()

def test_aggregate_script_exists():
    assert os.path.isfile('/home/user/aggregate.sh'), "The script /home/user/aggregate.sh does not exist."

def test_nginx_config_updated():
    with open('/app/gateway/nginx.conf', 'r') as f:
        content = f.read()
    assert 'proxy_pass' in content, "nginx.conf does not contain proxy_pass directives."
    assert '5001' in content, "nginx.conf does not proxy to the Metadata Service on port 5001."
    assert '5002' in content, "nginx.conf does not proxy to the Genomics Data Store on port 5002."

def test_jaccard_metric():
    # Ensure services are running
    subprocess.run(["bash", "/app/start_services.sh"], check=False)
    time.sleep(3)

    # Execute the user's script
    script_path = "/home/user/aggregate.sh"
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"aggregate.sh failed to execute. stderr: {result.stderr}"

    output_path = "/home/user/processed_dataset.json"
    truth_path = "/tests/ground_truth.json"

    assert os.path.isfile(output_path), f"Output file {output_path} was not created by the script."
    assert os.path.isfile(truth_path), f"Ground truth file {truth_path} is missing."

    pred = load_data(output_path)
    truth = load_data(truth_path)

    assert len(truth) > 0, "Ground truth dataset is empty or could not be loaded."

    intersection = len(pred.intersection(truth))
    union = len(pred.union(truth))

    jaccard = intersection / union if union > 0 else 0.0

    assert jaccard >= 0.99, f"Jaccard similarity {jaccard:.4f} is below the threshold of 0.99. Output data does not match the expected dataset."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
