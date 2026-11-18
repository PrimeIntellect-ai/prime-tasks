#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import tempfile

import pytest

RUN_SH = "/app/log_pipeline/run.sh"
PROCESS_PY = "/app/log_pipeline/process.py"
FILTER_BIN = "/app/log_pipeline/filter_bin"
REQUIREMENTS = "/app/log_pipeline/requirements.txt"
RAW_LOGS = "/home/user/raw_logs.txt"
FINAL_OUTPUT = "/home/user/processed_logs.jsonl"


def assert_required_artifacts():
    for path in (RUN_SH, PROCESS_PY, FILTER_BIN, REQUIREMENTS):
        assert os.path.isfile(path), f"Required pipeline artifact not found: {path}"
    assert os.access(RUN_SH, os.X_OK), f"Bash wrapper is not executable: {RUN_SH}"
    assert os.access(FILTER_BIN, os.X_OK), f"Filter binary is not executable: {FILTER_BIN}"
    mode = os.stat(FILTER_BIN).st_mode
    assert not stat.S_ISDIR(mode), f"Filter binary is not a file: {FILTER_BIN}"


def run_pipeline(input_path, output_path):
    if os.path.lexists(output_path):
        os.unlink(output_path)
    result = subprocess.run(
        ["timeout", "10s", RUN_SH, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, (
        f"Pipeline failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def read_agent_ids(path):
    assert os.path.exists(path), f"Agent's output file not found: {path}"
    assert os.path.isfile(path), f"Agent's output is not a regular file: {path}"

    agent_ids = set()
    with open(path, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON at line {line_num} in {path}")
            assert isinstance(data, dict), f"JSON value at line {line_num} is not an object"
            if "query_id" in data:
                agent_ids.add(str(data["query_id"]))

    assert len(agent_ids) > 0, "No query_ids found in the agent's output file."
    return agent_ids


def assert_f1(agent_ids, reference_ids):
    true_positives = len(agent_ids.intersection(reference_ids))
    false_positives = len(agent_ids - reference_ids)
    false_negatives = len(reference_ids - agent_ids)

    precision = true_positives / (true_positives + false_positives) if agent_ids else 0.0
    recall = true_positives / (true_positives + false_negatives) if reference_ids else 0.0
    f1_score = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)

    assert f1_score >= 0.95, (
        f"F1 score is {f1_score:.4f}, which is below the threshold of 0.95. "
        f"Precision: {precision:.4f}, Recall: {recall:.4f}"
    )


def test_pipeline_and_processed_logs_f1_score():
    assert_required_artifacts()
    assert os.path.isfile(RAW_LOGS), f"Raw logs file not found: {RAW_LOGS}"

    # Execute the exact command requested by the task and validate its known fixture.
    run_pipeline(RAW_LOGS, FINAL_OUTPUT)
    final_ids = read_agent_ids(FINAL_OUTPUT)
    assert_f1(final_ids, {"Q123", "Q456"})

    # Exercise the repaired pipeline on fresh IDs so a fabricated/stale final file
    # or a wrapper hard-coded to the fixture cannot pass.
    expected = {f"Q_{secrets.token_hex(8)}" for _ in range(5)}
    with tempfile.TemporaryDirectory() as tmpdir:
        challenge_input = os.path.join(tmpdir, "raw_logs.txt")
        challenge_output = os.path.join(tmpdir, "processed_logs.jsonl")
        ids = sorted(expected)
        with open(challenge_input, "w") as f:
            f.write("INFO startup complete\n")
            f.write(f"QUERY {ids[0]} select alpha\n")
            f.write("DEBUG unrelated message\n")
            f.write(f"QUERY {ids[1]} select beta\n")
            f.write(f"QUERY {ids[2]} drop gamma\n")
            f.write("WARNING no query here\n")
            f.write(f"QUERY {ids[3]} update delta\n")
            f.write(f"QUERY {ids[4]} insert epsilon\n")

        run_pipeline(challenge_input, challenge_output)
        challenge_ids = read_agent_ids(challenge_output)
        assert_f1(challenge_ids, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
