#!/bin/bash
set -e
mkdir -p /logs/verifier
chmod 600 /tests/true_logs.json

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import stat
import subprocess
import pytest


def _drop_to_user():
    user = pwd.getpwnam('user')
    os.setgroups([])
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


def test_recovered_logs_accuracy():
    truth_file = '/tests/true_logs.json'
    script_file = '/home/user/recover.py'
    pred_file = '/home/user/recovered_logs.json'

    assert os.path.isfile(truth_file), f"Truth file missing: {truth_file}"
    assert os.path.exists(script_file), f"Required script missing: {script_file}"
    script_stat = os.stat(script_file, follow_symlinks=False)
    assert stat.S_ISREG(script_stat.st_mode), f"Required script is not a regular file: {script_file}"

    if os.path.lexists(pred_file):
        os.unlink(pred_file)

    try:
        result = subprocess.run(
            ['python3', script_file],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
            preexec_fn=_drop_to_user,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{script_file} timed out")

    assert result.returncode == 0, (
        f"{script_file} exited with status {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(pred_file), f"Student output missing: {pred_file}"

    with open(truth_file, 'r') as f:
        try:
            truth = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse JSON from {truth_file}")

    with open(pred_file, 'r') as f:
        try:
            pred = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse JSON from {pred_file}")

    assert isinstance(truth, list), "Truth data should be a JSON array"
    assert isinstance(pred, list), "Student output should be a JSON array"

    truth_dict = {f"{r.get('ip', '')}|{r.get('timestamp', '')}": r for r in truth}
    pred_dict = {f"{r.get('ip', '')}|{r.get('timestamp', '')}": r for r in pred}

    correct = 0
    for k, v in truth_dict.items():
        if k in pred_dict and pred_dict[k] == v:
            correct += 1

    total = len(truth_dict)
    assert total > 0, "Truth data is empty"

    accuracy = correct / total
    threshold = 0.95

    assert accuracy >= threshold, f"Accuracy {accuracy:.4f} is below the threshold of {threshold}. {correct}/{total} correct records."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
