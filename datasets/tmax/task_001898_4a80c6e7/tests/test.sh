#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess

import pandas as pd
import pytest


def test_graph_builder_accuracy():
    events_path = '/home/user/events.csv'
    pipeline_path = '/home/user/pipeline.py'
    agent_commands_path = '/home/user/commands.txt'
    binary_path = '/app/graph_builder'

    assert os.path.isfile(events_path), f"Missing {events_path}"
    assert os.path.isfile(pipeline_path), f"Missing {pipeline_path}"
    assert os.path.isfile(binary_path), f"Missing {binary_path}"

    # Derive the expected commands from the supplied CSV before running the agent's
    # pipeline, so the generated output must reflect the original input state.
    df = pd.read_csv(events_path)
    df = df.sort_values(by=['src_node', 'timestamp'])
    df['rolling_avg'] = df.groupby('src_node')['amount'].transform(
        lambda x: x.rolling(3, min_periods=1).mean()
    )
    filtered = df[df['amount'] > df['rolling_avg']]
    filtered = filtered.sort_values(by=['src_node', 'timestamp'])

    expected_commands = [
        f"ADD EDGE {row['src_node']} {row['dst_node']} {row['amount']}"
        for _, row in filtered.iterrows()
    ]
    expected_commands_path = '/tmp/expected_commands.txt'
    with open(expected_commands_path, 'w') as f:
        for command in expected_commands:
            f.write(command + '\n')

    # Require pipeline.py itself to autonomously regenerate commands.txt.
    if os.path.lexists(agent_commands_path):
        os.remove(agent_commands_path)
    try:
        subprocess.run(
            ['python3', pipeline_path],
            cwd='/home/user',
            capture_output=True,
            text=True,
            timeout=120,
            check=True,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Executing {pipeline_path} failed: {exc}")

    assert os.path.isfile(agent_commands_path), (
        f"Missing {agent_commands_path}. The pipeline script must generate this file."
    )

    with open(agent_commands_path, 'r') as f:
        agent_commands = [line.strip() for line in f if line.strip()]

    # Every submitted command must be a correctly formatted, non-duplicated
    # occurrence of a filtered CSV row, in the required optimal order. Allowing a
    # subsequence preserves the original >=99% accuracy threshold.
    expected_index = 0
    for command in agent_commands:
        while expected_index < len(expected_commands) and expected_commands[expected_index] != command:
            expected_index += 1
        assert expected_index < len(expected_commands), (
            f"Command is fabricated, duplicated, incorrectly formatted, or out of order: {command!r}"
        )
        expected_index += 1

    def get_committed_edges(commands_file):
        with open(commands_file, 'r') as f:
            result = subprocess.run(
                [binary_path], stdin=f, capture_output=True, text=True, check=True
            )
        try:
            output = json.loads(result.stdout)
            return output.get('committed_edges', 0)
        except json.JSONDecodeError:
            pytest.fail(
                f"Failed to parse JSON output from {binary_path}. Output was: {result.stdout}"
            )

    golden_edges = get_committed_edges(expected_commands_path)
    agent_edges = get_committed_edges(agent_commands_path)

    assert golden_edges > 0, "Golden expected edges should be greater than 0."

    accuracy = agent_edges / golden_edges
    assert accuracy >= 0.99, (
        f"Accuracy metric failed. Agent committed edges: {agent_edges}, "
        f"Golden committed edges: {golden_edges}. Accuracy: {accuracy:.4f} "
        f"(Threshold: >= 0.99)"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
