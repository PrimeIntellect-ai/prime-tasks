#!/bin/bash
set -e
mkdir -p /logs/verifier

# Restore the advertised initial state before exercising the submitted pipeline.
cat > /app/api/config.ini <<'EOF'
[DEFAULT]
CACHE_HOST=redis-db
CACHE_PORT=6379
EOF
chmod 777 /app/api/config.ini

redis-cli ping >/dev/null 2>&1 || redis-server --daemonize yes
pkill -f '/app/api/server.py' >/dev/null 2>&1 || true
runuser -u user -- sh -c 'nohup python3 /app/api/server.py >/tmp/sequence-api.log 2>&1 &'
sleep 1

# The output must be produced by this execution, not left behind beforehand.
rm -f /home/user/candidate_scores.csv
run_status=0
timeout 60s runuser -u user -- /home/user/process_pipeline.sh || run_status=$?
echo "$run_status" > /tmp/pipeline_run_status

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import configparser
import urllib.request
import json


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/process_pipeline.sh"
    assert os.path.exists(script_path), f"Pipeline script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Pipeline script is not executable: {script_path}"


def test_pipeline_executed_successfully():
    with open('/tmp/pipeline_run_status', 'r') as f:
        status = int(f.read().strip())
    assert status == 0, f"Pipeline exited with status {status}"


def test_api_was_reconfigured_and_restarted():
    config = configparser.ConfigParser()
    config.read('/app/api/config.ini')
    assert config['DEFAULT'].get('CACHE_HOST') == 'localhost'
    assert config['DEFAULT'].get('CACHE_PORT') == '6379'
    with urllib.request.urlopen('http://127.0.0.1:8000/api/v1/sequences', timeout=5) as response:
        assert response.status == 200
        assert json.load(response) == ['seq1', 'seq2']


def test_candidate_scores_mse():
    candidate_path = "/home/user/candidate_scores.csv"
    truth_path = "/tests/ground_truth.csv"

    assert os.path.exists(candidate_path), f"Output file missing: {candidate_path}"
    assert os.path.exists(truth_path), f"Ground truth file missing: {truth_path}"

    truth_scores = {}
    with open(truth_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or row[0] == "Sequence_ID":
                continue
            seq_id, score = row[0], float(row[1])
            truth_scores[seq_id] = score

    candidate_scores = {}
    with open(candidate_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or row[0] == "Sequence_ID":
                continue
            seq_id, score = row[0], float(row[1])
            candidate_scores[seq_id] = score

    assert len(candidate_scores) > 0, "Candidate scores file is empty or invalid"
    assert set(candidate_scores.keys()) == set(truth_scores.keys()), "Candidate sequence IDs do not match ground truth sequence IDs"

    squared_errors = []
    for seq_id in truth_scores:
        diff = candidate_scores[seq_id] - truth_scores[seq_id]
        squared_errors.append(diff ** 2)

    mse = sum(squared_errors) / len(squared_errors)
    threshold = 0.01
    assert mse <= threshold, f"MSE of Alignment Scores is {mse:.6f}, which exceeds the threshold of {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
