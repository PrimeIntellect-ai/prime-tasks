#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import subprocess

import pytest

PIPELINE_PATH = '/home/user/pipeline.py'
SHELL_PATH = '/home/user/run_pipeline.sh'
DATA_PATH = '/home/user/math_raw.csv'
METRICS_PATH = '/home/user/metrics.json'


def test_scripts_exist():
    """Verify that the required scripts have been created."""
    assert os.path.isfile(PIPELINE_PATH), f"Python script {PIPELINE_PATH} is missing."
    assert os.path.isfile(SHELL_PATH), f"Shell script {SHELL_PATH} is missing."
    assert os.access(SHELL_PATH, os.X_OK), f"Shell script {SHELL_PATH} is not executable."


def run_artifact(command):
    if os.path.exists(METRICS_PATH):
        os.remove(METRICS_PATH)
    result = subprocess.run(
        command,
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f"Command {command!r} failed:\n{result.stdout}"
    assert os.path.isfile(METRICS_PATH), f"Output file {METRICS_PATH} is missing."


def load_metrics():
    with open(METRICS_PATH, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS_PATH} does not contain valid JSON.")
    assert set(metrics.keys()) == {'total_rows', 'total_tokens', 'total_cost'}, \
        "metrics.json must contain exactly total_rows, total_tokens, and total_cost."
    assert type(metrics['total_rows']) is int, "total_rows must be an integer."
    assert type(metrics['total_tokens']) is int, "total_tokens must be an integer."
    assert type(metrics['total_cost']) is float, "total_cost must be a float."
    return metrics


def expected_for(rows):
    import tiktoken
    encoding = tiktoken.get_encoding('cl100k_base')
    total_tokens = 0
    for _, text in rows:
        cleaned = re.sub(r'<[^>]*>', '', text)
        cleaned = re.sub(r'\s+', ' ', cleaned).strip()
        total_tokens += len(encoding.encode(cleaned))
    return {
        'total_rows': len(rows),
        'total_tokens': total_tokens,
        'total_cost': round(total_tokens * 0.0002, 4),
    }


def write_rows(rows):
    with open(DATA_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'text'])
        writer.writerows(rows)


def assert_metrics(metrics, expected_metrics):
    assert "total_rows" in metrics, "Key 'total_rows' is missing from metrics.json."
    assert "total_tokens" in metrics, "Key 'total_tokens' is missing from metrics.json."
    assert "total_cost" in metrics, "Key 'total_cost' is missing from metrics.json."
    assert metrics['total_rows'] == expected_metrics['total_rows'], \
        f"Expected total_rows to be {expected_metrics['total_rows']}, got {metrics['total_rows']}."
    assert metrics['total_tokens'] == expected_metrics['total_tokens'], \
        f"Expected total_tokens to be {expected_metrics['total_tokens']}, got {metrics['total_tokens']}."
    assert metrics['total_cost'] == expected_metrics['total_cost'], \
        f"Expected total_cost to be {expected_metrics['total_cost']}, got {metrics['total_cost']}."


def test_metrics_json_exists_and_correct():
    """Execute both artifacts and verify original and fresh behavioral cases."""
    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    try:
        # Preserve the original verifier's assertions, but require the shell artifact
        # to produce the file rather than accepting a pre-created metrics.json.
        run_artifact([SHELL_PATH])
        expected_metrics = {
            'total_rows': 3,
            'total_tokens': 32,
            'total_cost': 0.0064,
        }
        assert_metrics(load_metrics(), expected_metrics)

        # Exercise the shell entry point on unpredictable input.
        nonce = secrets.token_hex(12)
        shell_rows = [
            (11, f"<h1>  Fresh   value {nonce} </h1>"),
            (27, "<div>\tSolve   y: <b>  7y + 1 = 22 </b>\n</div>"),
            (35, "<p></p>"),
            (49, "  Plain\n\nmathematical   text.  "),
        ]
        write_rows(shell_rows)
        run_artifact([SHELL_PATH])
        assert_metrics(load_metrics(), expected_for(shell_rows))

        # Execute pipeline.py itself on another fresh case.
        nonce2 = secrets.token_urlsafe(15)
        python_rows = [
            (101, f"<section><em>{nonce2}</em>   squared is positive</section>"),
            (102, "<span class='math'>  \\int_0^2   x dx = 2 </span>"),
        ]
        write_rows(python_rows)
        run_artifact(['python3', PIPELINE_PATH])
        assert_metrics(load_metrics(), expected_for(python_rows))
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
