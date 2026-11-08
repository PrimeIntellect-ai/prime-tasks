#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile
from collections import defaultdict

import pytest


def compute_expected_ema():
    """Derive the expected EMA values from the raw logs based on the schema and formula."""
    records = []
    for fpath in glob.glob('/home/user/raw_logs/*.jsonl'):
        with open(fpath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    exp_id = data.get("experiment_id")
                    epoch = data.get("epoch")
                    val_loss = data.get("val_loss")

                    # Schema enforcement
                    if not isinstance(exp_id, str):
                        continue
                    if not isinstance(epoch, int) or isinstance(epoch, bool) or epoch < 0:
                        continue

                    try:
                        val_loss = float(val_loss)
                    except (ValueError, TypeError):
                        continue

                    if math.isnan(val_loss) or val_loss <= 0:
                        continue

                    records.append((exp_id, epoch, val_loss))
                except Exception:
                    pass

    grouped = defaultdict(list)
    for exp_id, epoch, val_loss in records:
        grouped[exp_id].append((epoch, val_loss))

    emas = {}
    for exp_id, items in grouped.items():
        items.sort(key=lambda x: x[0])
        ema = items[0][1]
        for epoch, val_loss in items[1:]:
            ema = 0.2 * val_loss + 0.8 * ema
        emas[exp_id] = round(ema, 4)

    return emas


def test_summary_json_exists_and_correct():
    summary_path = '/home/user/artifacts/summary.json'
    assert os.path.exists(summary_path), f"Output file {summary_path} does not exist."
    assert os.path.isfile(summary_path), f"Path {summary_path} is not a file."

    with open(summary_path, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_path} does not contain valid JSON.")

    expected_data = compute_expected_ema()

    for exp_id, expected_ema in expected_data.items():
        assert exp_id in actual_data, f"Experiment {exp_id} is missing from the output."
        actual_ema = actual_data[exp_id]
        assert abs(actual_ema - expected_ema) < 1e-4, \
            f"EMA for {exp_id} is incorrect. Expected ~{expected_ema}, got {actual_ema}."


def test_scripts_exist_and_executable():
    pipeline_script = '/home/user/run_pipeline.sh'
    process_script = '/home/user/process_metrics.py'

    assert os.path.exists(pipeline_script), f"Bash script {pipeline_script} does not exist."
    assert os.access(pipeline_script, os.X_OK), f"Bash script {pipeline_script} is not executable."
    assert os.path.exists(process_script), f"Python script {process_script} does not exist."


def expected_from_records(records):
    grouped = defaultdict(list)
    for exp_id, epoch, loss in records:
        grouped[exp_id].append((epoch, float(loss)))
    result = {}
    for exp_id, items in grouped.items():
        items.sort(key=lambda item: item[0])
        ema = items[0][1]
        for _, loss in items[1:]:
            ema = 0.2 * loss + 0.8 * ema
        result[exp_id] = round(ema, 4)
    return result


def write_jsonl(path, rows, malformed=False):
    with open(path, 'w') as f:
        for row in rows:
            f.write(json.dumps(row) + '\n')
        if malformed:
            f.write('{this is not valid json\n')
            f.write('\n')


def assert_summary(expected):
    summary = '/home/user/artifacts/summary.json'
    assert os.path.isfile(summary), 'Pipeline did not create artifacts/summary.json.'
    with open(summary) as f:
        actual = json.load(f)
    assert isinstance(actual, dict)
    assert set(actual) == set(expected), \
        f"Output experiments differ: expected {set(expected)}, got {set(actual)}"
    for exp_id, value in expected.items():
        assert isinstance(actual[exp_id], (int, float)) and not isinstance(actual[exp_id], bool)
        assert math.isfinite(actual[exp_id])
        assert abs(actual[exp_id] - value) < 1e-4, \
            f"EMA for {exp_id} is incorrect: expected {value}, got {actual[exp_id]}"


def test_pipeline_and_python_process_changed_inputs():
    home = '/home/user'
    raw = os.path.join(home, 'raw_logs')
    artifacts = os.path.join(home, 'artifacts')
    venv = os.path.join(home, 'venv')
    backup = tempfile.mkdtemp(prefix='pipeline-verifier-')
    raw_backup = os.path.join(backup, 'raw_logs')
    artifacts_backup = os.path.join(backup, 'artifacts')
    venv_backup = os.path.join(backup, 'venv')

    shutil.copytree(raw, raw_backup)
    if os.path.exists(artifacts):
        shutil.copytree(artifacts, artifacts_backup)
    if os.path.exists(venv):
        os.rename(venv, venv_backup)

    try:
        shutil.rmtree(raw)
        os.makedirs(raw)
        shutil.rmtree(artifacts, ignore_errors=True)

        token = secrets.token_hex(6)
        exp_a = 'DYNAMIC_A_' + token
        exp_b = 'DYNAMIC_B_' + token
        base = 1.0 + secrets.randbelow(500) / 100.0
        valid = [
            (exp_a, 0, base + 1.1),
            (exp_a, 3, base + 0.2),
            (exp_a, 8, base + 2.4),
            (exp_b, 1, base + 0.7),
            (exp_b, 4, base + 1.8),
        ]
        write_jsonl(os.path.join(raw, 'changed_1.jsonl'), [
            {'experiment_id': exp_a, 'epoch': 8, 'val_loss': valid[2][2]},
            {'experiment_id': exp_a, 'epoch': 0, 'val_loss': valid[0][2]},
            {'experiment_id': exp_b, 'epoch': -1, 'val_loss': 99.0},
            {'experiment_id': 123, 'epoch': 2, 'val_loss': 99.0},
            {'experiment_id': exp_a, 'epoch': True, 'val_loss': 99.0},
            {'experiment_id': exp_b, 'epoch': 1, 'val_loss': str(valid[3][2])},
        ], malformed=True)
        write_jsonl(os.path.join(raw, 'changed_2.jsonl'), [
            {'experiment_id': exp_a, 'epoch': 3, 'val_loss': valid[1][2]},
            {'experiment_id': exp_b, 'epoch': 4, 'val_loss': valid[4][2]},
            {'experiment_id': exp_b, 'epoch': 9, 'val_loss': 0},
            {'experiment_id': exp_a, 'epoch': 9, 'val_loss': -5},
            {'experiment_id': exp_a, 'epoch': 10, 'val_loss': 'NaN'},
            {'experiment_id': exp_b, 'epoch': 11, 'val_loss': 'not-a-number'},
        ])

        completed = subprocess.run(
            ['/home/user/run_pipeline.sh'], cwd=home,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=180
        )
        assert completed.returncode == 0, \
            f"run_pipeline.sh failed with output:\n{completed.stdout}"
        assert os.path.isfile(os.path.join(venv, 'bin', 'python')), \
            'run_pipeline.sh did not create the required Python virtual environment.'
        assert_summary(expected_from_records(valid))

        # Replace the inputs again and invoke the required Python ETL artifact directly.
        shutil.rmtree(raw)
        os.makedirs(raw)
        shutil.rmtree(artifacts, ignore_errors=True)
        exp_c = 'DIRECT_' + secrets.token_hex(6)
        shift = secrets.randbelow(700) / 100.0
        direct_valid = [
            (exp_c, 2, 2.25 + shift),
            (exp_c, 6, 0.75 + shift),
            (exp_c, 9, 1.50 + shift),
        ]
        write_jsonl(os.path.join(raw, 'direct.jsonl'), [
            {'experiment_id': exp_c, 'epoch': 9, 'val_loss': direct_valid[2][2]},
            {'experiment_id': exp_c, 'epoch': 2, 'val_loss': direct_valid[0][2]},
            {'experiment_id': exp_c, 'epoch': 6, 'val_loss': str(direct_valid[1][2])},
            {'experiment_id': exp_c, 'epoch': -3, 'val_loss': 1000},
            {'experiment_id': exp_c, 'epoch': 10, 'val_loss': None},
        ], malformed=True)
        completed = subprocess.run(
            [os.path.join(venv, 'bin', 'python'), '/home/user/process_metrics.py'],
            cwd=home, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=60
        )
        assert completed.returncode == 0, \
            f"process_metrics.py failed with output:\n{completed.stdout}"
        assert_summary(expected_from_records(direct_valid))
    finally:
        shutil.rmtree(raw, ignore_errors=True)
        shutil.copytree(raw_backup, raw)
        shutil.rmtree(artifacts, ignore_errors=True)
        if os.path.exists(artifacts_backup):
            shutil.copytree(artifacts_backup, artifacts)
        shutil.rmtree(venv, ignore_errors=True)
        if os.path.exists(venv_backup):
            os.rename(venv_backup, venv)
        shutil.rmtree(backup, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
