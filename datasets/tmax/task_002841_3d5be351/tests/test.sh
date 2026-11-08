#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import glob
import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

def test_top_experiments_file_exists():
    file_path = '/home/user/top_experiments.txt'
    assert os.path.exists(file_path), f"Expected output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a valid file."

def test_top_experiments_content():
    artifacts_dir = '/home/user/artifacts'
    json_files = sorted(glob.glob(os.path.join(artifacts_dir, '*.json')))

    assert len(json_files) > 0, f"No JSON files found in {artifacts_dir} to evaluate."

    success_docs = []
    success_ids = []

    for fpath in json_files:
        with open(fpath, 'r') as f:
            data = json.load(f)
            if data.get('status') == 'SUCCESS':
                hp = data['hyperparameters']
                hp_str = " ".join([f"{k}={hp[k]}" for k in sorted(hp.keys())])
                success_docs.append(hp_str)
                success_ids.append(data['experiment_id'])

    vectorizer = TfidfVectorizer(analyzer='char_wb', ngram_range=(2,3), lowercase=True)
    X = vectorizer.fit_transform(success_docs)

    target_hp = {"batch_size": 32, "lr": 0.005, "optimizer": "adam", "dropout": 0.2}
    target_str = " ".join([f"{k}={target_hp[k]}" for k in sorted(target_hp.keys())])
    target_vec = vectorizer.transform([target_str])

    sims = cosine_similarity(target_vec, X)[0]
    top_indices = sims.argsort()[-3:][::-1]

    expected_ids = [success_ids[i] for i in top_indices]

    file_path = '/home/user/top_experiments.txt'
    assert os.path.exists(file_path), f"Expected output file {file_path} does not exist."

    with open(file_path, 'r') as f:
        agent_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(agent_lines) == 3, f"Expected exactly 3 experiment IDs in {file_path}, got {len(agent_lines)}."
    assert agent_lines == expected_ids, f"Incorrect top experiments. Expected {expected_ids}, got {agent_lines}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
