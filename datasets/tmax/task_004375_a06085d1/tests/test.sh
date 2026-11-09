#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import string
import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

def reference_scores_and_logs():
    with open("/app/logs.json", "r") as f:
        logs = json.load(f)

    def tokenize(text):
        text = text.lower()
        text = text.translate(str.maketrans('', '', string.punctuation))
        return text

    corpus = [tokenize(log['log_text']) for log in logs]
    ids = [log['id'] for log in logs]

    vectorizer = TfidfVectorizer(token_pattern=r"(?u)\b\w+\b")
    X = vectorizer.fit_transform(corpus)

    query = tokenize("memory leak in distributed training module")
    q_vec = vectorizer.transform([query])

    sims = cosine_similarity(q_vec, X)[0]

    df = pd.DataFrame({'id': ids, 'score': sims})
    df = df.sort_values('id').reset_index(drop=True)
    return df, logs

def test_similarities_csv_mae():
    agent_csv_path = "/app/similarities.csv"
    assert os.path.exists(agent_csv_path), f"{agent_csv_path} is missing."

    agent_df = pd.read_csv(agent_csv_path)
    assert list(agent_df.columns) == ['id', 'score'], \
        f"Expected header id,score in {agent_csv_path}, found {list(agent_df.columns)}."

    ref_df, _ = reference_scores_and_logs()
    assert len(agent_df) == len(ref_df), f"Expected {len(ref_df)} rows in {agent_csv_path}, found {len(agent_df)}."

    agent_ids = pd.to_numeric(agent_df['id'], errors='coerce').to_numpy(dtype=float)
    agent_scores = pd.to_numeric(agent_df['score'], errors='coerce').to_numpy(dtype=float)
    assert np.isfinite(agent_ids).all(), "All submitted IDs must be finite numeric values."
    assert np.isfinite(agent_scores).all(), "All submitted similarity scores must be finite numeric values."

    agent_df = agent_df.copy()
    agent_df['id'] = agent_ids
    agent_df['score'] = agent_scores
    agent_df = agent_df.sort_values('id').reset_index(drop=True)

    assert np.array_equal(agent_df['id'].to_numpy(dtype=float), ref_df['id'].to_numpy(dtype=float)), \
        f"Submitted IDs do not match the IDs in /app/logs.json."

    mae = (agent_df['score'] - ref_df['score']).abs().mean()
    assert np.isfinite(mae), "MAE of similarity scores is not finite."
    assert mae <= 0.02, f"MAE of similarity scores is {mae:.4f}, which exceeds the threshold of 0.02."

def test_cov_trace():
    trace_path = "/app/cov_trace.txt"
    assert os.path.exists(trace_path), f"{trace_path} is missing."

    with open(trace_path, "r") as f:
        agent_trace_str = f.read().strip()

    try:
        agent_trace = float(agent_trace_str)
    except ValueError:
        assert False, f"Could not parse '{agent_trace_str}' as a float in {trace_path}."

    assert np.isfinite(agent_trace), f"Covariance trace must be finite, found {agent_trace_str}."

    ref_df, logs = reference_scores_and_logs()
    filtered_ids = set(ref_df[ref_df['score'] > 0.05]['id'])

    filtered_logs = [log for log in logs if log['id'] in filtered_ids]

    if len(filtered_logs) > 1:
        latencies = [log['latency_ms'] for log in filtered_logs]
        vrams = [log['vram_mb'] for log in filtered_logs]
        cov_matrix = np.cov(latencies, vrams)
        ref_trace = np.trace(cov_matrix)
    else:
        ref_trace = 0.0

    # Allow a small margin of error for floating point differences
    error = abs(agent_trace - ref_trace)
    assert error <= 1e-1 or (ref_trace != 0 and error / ref_trace <= 0.05), \
        f"Covariance trace {agent_trace} does not match expected {ref_trace}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
