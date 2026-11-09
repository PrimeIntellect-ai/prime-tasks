#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import time
import json
import struct
import secrets
import subprocess
import numpy as np
import pandas as pd

def compute_ground_truth():
    products_path = "/home/user/data/products.csv"
    descriptions_path = "/home/user/data/descriptions.json"

    # Read products
    products_df = pd.read_csv(products_path)

    # Read descriptions
    desc_records = []
    with open(descriptions_path, "r") as f:
        for line in f:
            if line.strip():
                desc_records.append(json.loads(line))
    desc_df = pd.DataFrame(desc_records)
    desc_df = desc_df.rename(columns={"id": "product_id"})

    # Join and sort
    merged = pd.merge(products_df, desc_df, on="product_id")
    merged = merged.sort_values("product_id", ascending=True).reset_index(drop=True)

    # Format text
    texts = []
    for _, row in merged.iterrows():
        text = f"[{row['category']}] {row['name']} - {row['desc']}"
        texts.append(text)

    input_text = "\n".join(texts) + "\n"

    # Run feature extractor
    process = subprocess.Popen(
        ["/app/feature_extractor"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    stdout_data, stderr_data = process.communicate(input=input_text.encode("utf-8"))

    # Parse output: 64 floats (little-endian single precision) per record
    num_records = len(texts)
    bytes_per_record = 64 * 4
    expected_bytes = num_records * bytes_per_record

    if len(stdout_data) < expected_bytes:
        raise RuntimeError(f"Feature extractor output too short. Expected {expected_bytes}, got {len(stdout_data)}")

    embeddings = []
    for i in range(num_records):
        record_bytes = stdout_data[i*bytes_per_record : (i+1)*bytes_per_record]
        floats = struct.unpack("<64f", record_bytes)
        embeddings.append(floats)

    embeddings = np.array(embeddings, dtype=np.float32)

    # Normalize embeddings for cosine similarity
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    norms[norms == 0] = 1e-10
    normalized_embeddings = embeddings / norms

    product_ids = merged["product_id"].values
    id_to_idx = {pid: idx for idx, pid in enumerate(product_ids)}

    return normalized_embeddings, product_ids, id_to_idx

def test_recommend_script():
    script_path = "/home/user/recommend.py"
    assert os.path.isfile(script_path), f"Missing script at {script_path}"

    embeddings, product_ids, id_to_idx = compute_ground_truth()

    test_queries = [10, 500, 1200, 4500, 8000]

    # Ensure test queries exist in the dataset
    valid_queries = [q for q in test_queries if q in id_to_idx]
    if not valid_queries:
        # Fallback to some existing IDs if the specific ones aren't there
        valid_queries = product_ids[:5].tolist()

    # Add unpredictable queries so query-specific hardcoded answers cannot pass.
    used = {int(q) for q in valid_queries}
    random_candidates = [int(pid) for pid in product_ids if int(pid) not in used]
    random_count = min(10, len(random_candidates))
    valid_queries.extend(secrets.SystemRandom().sample(random_candidates, random_count))

    total_recall = 0.0
    total_time = 0.0

    for q_id in valid_queries:
        # Compute exact ground truth
        q_idx = id_to_idx[q_id]
        q_emb = embeddings[q_idx]

        similarities = np.dot(embeddings, q_emb)
        # Exclude query itself
        similarities[q_idx] = -np.inf

        # Get top 10
        top10_idx = np.argsort(similarities)[-10:][::-1]
        truth_ids = set(product_ids[top10_idx])

        # Run agent script
        start = time.time()
        try:
            out = subprocess.check_output(['python3', script_path, str(q_id)], text=True, timeout=5.0)
        except subprocess.TimeoutExpired:
            assert False, f"Script timed out for query {q_id}"
        except subprocess.CalledProcessError as e:
            assert False, f"Script failed for query {q_id}: {e}"

        elapsed = time.time() - start
        total_time += elapsed

        try:
            preds = [int(x.strip()) for x in out.strip().split(',')]
        except ValueError:
            assert False, f"Output format invalid for query {q_id}. Expected comma-separated integers, got: {out.strip()}"

        assert len(preds) == 10, f"Expected exactly 10 product IDs for query {q_id}, got {len(preds)}"
        assert len(set(preds)) == 10, f"Expected 10 distinct product IDs for query {q_id}, got: {out.strip()}"

        hits = len(set(preds).intersection(truth_ids))
        total_recall += hits / 10.0

    avg_recall = total_recall / len(valid_queries)
    avg_time = total_time / len(valid_queries)

    assert avg_recall >= 0.95, f"Recall@10 is {avg_recall:.2f}, expected >= 0.95"
    assert avg_time < 0.5, f"Average latency is {avg_time:.3f}s, expected < 0.5s"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
