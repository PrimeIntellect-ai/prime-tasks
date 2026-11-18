#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import subprocess
import sys
import os

def test_decode_traffic_accuracy():
    agent_script = "/home/user/decode_traffic.py"
    key = "K3yM4st3r2024XOR"
    eval_pcap = "/app/eval.pcap"
    output_json = "/home/user/decoded_payloads.json"
    truth_json = "/tests/eval_ground_truth.json"

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.exists(eval_pcap), f"Eval pcap {eval_pcap} does not exist."
    assert os.path.exists(truth_json), f"Ground truth json {truth_json} does not exist."

    # Run the agent's script
    try:
        subprocess.run([sys.executable, agent_script, eval_pcap, key], timeout=60, check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        assert False, f"Agent script failed with exit code {e.returncode}. Stderr: {e.stderr.decode()}"
    except subprocess.TimeoutExpired:
        assert False, "Agent script timed out after 60 seconds."

    assert os.path.exists(output_json), f"Output JSON {output_json} was not created."

    # Load agent results
    with open(output_json, 'r') as f:
        try:
            agent_results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Output JSON {output_json} is not valid JSON."

    assert isinstance(agent_results, list), "Output JSON must be a list of objects."

    # Load ground truth
    with open(truth_json, 'r') as f:
        truth_results = json.load(f)

    # Calculate accuracy
    correct = 0
    agent_dict = {item.get('packet_index'): item for item in agent_results if isinstance(item, dict) and 'packet_index' in item}

    for truth_item in truth_results:
        idx = truth_item['packet_index']
        if idx in agent_dict:
            agent_item = agent_dict[idx]
            if agent_item.get('username') == truth_item['username'] and agent_item.get('token') == truth_item['token']:
                correct += 1

    total_truth = len(truth_results)
    accuracy = correct / total_truth if total_truth > 0 else 0.0

    assert accuracy >= 0.95, f"Accuracy {accuracy:.4f} is below the threshold of 0.95. Correctly decoded {correct} out of {total_truth} packets."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
