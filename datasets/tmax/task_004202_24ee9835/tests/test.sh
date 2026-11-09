#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
from difflib import SequenceMatcher

def test_timeline_similarity():
    agent_file = "/home/user/timeline.json"
    golden_file = "/tests/golden_timeline.json"

    assert os.path.exists(agent_file), f"Agent output file {agent_file} not found. Ensure your script writes to this exact path."
    assert os.path.exists(golden_file), f"Golden reference file {golden_file} not found."

    with open(agent_file, "r") as f:
        try:
            agent_json = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {agent_file} is not valid JSON."

    with open(golden_file, "r") as f:
        golden_json = json.load(f)

    # Format data for comparison as specified in the evaluation metric
    try:
        agent_data = [f"{e['timestamp']}-{e['event_id']}" for e in agent_json]
    except KeyError as e:
        assert False, f"Agent JSON objects are missing the expected key: {e}. Ensure keys are 'timestamp' and 'event_id'."
    except TypeError:
        assert False, f"Agent JSON should be a list of dictionaries, but got {type(agent_json).__name__}."

    golden_data = [f"{e['timestamp']}-{e['event_id']}" for e in golden_json]

    ratio = SequenceMatcher(None, agent_data, golden_data).ratio()
    threshold = 0.95

    assert ratio >= threshold, f"Timeline similarity ratio {ratio:.4f} is below the {threshold} threshold. Ensure you have correctly parsed and sorted all telemetry drops."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
