#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess

import numpy as np
import pytest


def test_output_exists():
    output_path = "/home/user/output.jsonl"
    assert os.path.exists(output_path), f"Output file is missing at {output_path}"
    assert os.path.isfile(output_path), f"Output path at {output_path} is not a file"


def test_embedding_mse():
    output_path = "/home/user/output.jsonl"
    data_path = "/app/data/events.csv"
    encoder_path = "/app/legacy_encoder"

    assert os.path.exists(output_path), f"Output file is missing at {output_path}"
    assert os.path.exists(data_path), f"Input CSV is missing at {data_path}"
    assert os.path.exists(encoder_path), f"Legacy encoder is missing at {encoder_path}"

    users = {}
    with open(data_path, "r", newline="") as f:
        for row in csv.DictReader(f):
            users.setdefault(row["user_id"], []).append(row)

    ref_data = {}
    for uid, rows in users.items():
        rows.sort(key=lambda row: row["timestamp"])
        concatenated = " ".join(row["item_name"] for row in rows)
        sanitized = re.sub(r"[^a-zA-Z0-9 ]", "", concatenated)
        encoded = subprocess.check_output([encoder_path, sanitized], text=True).strip()
        ref_data[uid] = np.array([float(x) for x in encoded.split(",")], dtype=np.float32)

    out_data = {}
    with open(output_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
                out_data[obj["user_id"]] = np.array(obj["embedding"], dtype=np.float32)
            except Exception as e:
                pytest.fail(f"Failed to parse line in output.jsonl: {line}. Error: {e}")

    ref_users = set(ref_data.keys())
    out_users = set(out_data.keys())

    missing_users = ref_users - out_users
    extra_users = out_users - ref_users

    assert not missing_users, f"Output is missing user_ids: {missing_users}"
    assert not extra_users, f"Output contains extra user_ids: {extra_users}"

    mses = []
    for uid in ref_users:
        ref_emb = ref_data[uid]
        out_emb = out_data[uid]

        assert len(ref_emb) == 32, f"Reference embedding for {uid} does not have 32 dimensions"
        assert len(out_emb) == 32, f"Output embedding for {uid} does not have 32 dimensions"

        mse = np.mean((ref_emb - out_emb) ** 2)
        mses.append(mse)

    overall_mse = float(np.mean(mses))
    threshold = 1e-5

    assert overall_mse <= threshold, f"Overall MSE {overall_mse} exceeds threshold {threshold}"


def test_go_source_exists():
    source_path = "/home/user/etl.go"
    assert os.path.exists(source_path), f"Go source file is missing at {source_path}"
    assert os.path.isfile(source_path), f"Go source path at {source_path} is not a file"


def test_go_binary_exists():
    binary_path = "/home/user/etl"
    assert os.path.exists(binary_path), f"Go binary is missing at {binary_path}"
    assert os.path.isfile(binary_path), f"Go binary path at {binary_path} is not a file"
    assert os.access(binary_path, os.X_OK), f"Go binary at {binary_path} is not executable"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
