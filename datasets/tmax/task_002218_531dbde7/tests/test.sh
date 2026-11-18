#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import pytest

def generate_random_sentence():
    words = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "hello", "world", "test", "data"]
    length = random.randint(5, 20)
    return " ".join(random.choices(words, k=length))

def test_package_fixed():
    """Verify that the vendored package bug was fixed."""
    processor_path = "/app/text_feature_toolkit/text_feature_toolkit/processor.py"
    assert os.path.isfile(processor_path), f"Processor file {processor_path} does not exist."
    with open(processor_path, "r") as f:
        content = f.read()
    assert 'how="inner"' in content or "how='inner'" in content, "The bug (how='left' in pd.merge) was not fixed to 'inner' in processor.py."

def test_fuzz_equivalence():
    """Fuzz equivalence test comparing the agent script to the oracle."""
    oracle_path = "/tests/oracle_processor"
    agent_script = "/home/user/process_stream.py"

    assert os.path.isfile(oracle_path), f"Oracle processor {oracle_path} not found."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} not found."

    random.seed(42)

    for i in range(1000):
        text = generate_random_sentence()
        meta_id = random.randint(1, 500)
        input_data = json.dumps({"text": text, "meta_id": meta_id})

        # Run oracle uploaded only at verification time.
        oracle_proc = subprocess.run(
            ["/usr/bin/python3", oracle_path],
            input=input_data,
            text=True,
            capture_output=True
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ["/usr/bin/python3", agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch for input: {input_data}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}\n"
            f"Agent stderr: {agent_proc.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
