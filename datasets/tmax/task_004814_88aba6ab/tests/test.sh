#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import numpy as np
import pandas as pd


def gold_values(df, gold_map, global_mean):
    return df['category'].map(lambda cat: gold_map.get(cat, global_mean)).to_numpy(dtype=float)


def validate_output(path, input_df, expected):
    assert os.path.exists(path), f"{os.path.basename(path)} was not created in the working directory."

    agent_out = pd.read_csv(path)
    assert 'id' in agent_out.columns and 'encoded_target' in agent_out.columns, \
        "Output CSV missing required columns 'id' and 'encoded_target'."
    assert list(agent_out.columns) == ['id', 'encoded_target'], \
        "Output CSV must contain exactly the columns 'id,encoded_target' in that order."
    assert len(agent_out) == len(input_df), "Output row count mismatch or missing IDs."
    assert agent_out['id'].tolist() == input_df['id'].tolist(), \
        "Output IDs do not preserve the original row order."

    # Retain the original ID-coverage assertion as well as the stricter order check.
    merged = pd.merge(input_df, agent_out, on='id')
    assert len(merged) == len(input_df), "Output row count mismatch or missing IDs."

    encoded = pd.to_numeric(agent_out['encoded_target'], errors='coerce').to_numpy(dtype=float)
    assert np.all(np.isfinite(encoded)), "encoded_target contains non-numeric or non-finite values."
    max_err = np.max(np.abs(expected - encoded)) if len(expected) else 0.0
    threshold = 1e-4
    assert max_err <= threshold, f"Max AE metric {max_err} exceeds threshold {threshold}"


def test_fast_etl_correctness():
    cpp_file = "/home/user/fast_etl.cpp"
    assert os.path.exists(cpp_file), f"Source file {cpp_file} not found."
    assert os.path.isfile(cpp_file), f"Source path {cpp_file} is not a regular file."

    executable = "/home/user/fast_etl"
    compile_cmd = ["g++", "-O3", "-std=c++17", cpp_file, "-o", executable]
    res = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert res.returncode == 0, f"Compilation failed:\n{res.stderr}"

    # Runtime-generated cases prevent submissions from hardcoding a fixed answer set.
    rng = np.random.default_rng(secrets.randbits(128))
    for case_num, (train_size, test_size) in enumerate([(73, 41), (127, 59), (46, 37)]):
        token = secrets.token_hex(5)
        seen = [f"cat_{token}_{i}" for i in range(4)]
        unseen = f"unseen_{token}"

        train_categories = rng.choice(seen, train_size, p=[0.12, 0.23, 0.29, 0.36])
        train_categories[:4] = seen
        rng.shuffle(train_categories)

        test_categories = rng.choice(seen + [unseen], test_size,
                                     p=[0.15, 0.20, 0.20, 0.20, 0.25])
        test_categories[0] = unseen
        rng.shuffle(test_categories)

        train_ids = rng.permutation(np.arange(1000000 + case_num * 10000,
                                              1000000 + case_num * 10000 + train_size))
        test_ids = rng.permutation(np.arange(2000000 + case_num * 10000,
                                             2000000 + case_num * 10000 + test_size))

        train_df = pd.DataFrame({
            'id': train_ids,
            'category': train_categories,
            'target': rng.normal(loc=50.0 + case_num * 3.0, scale=11.0, size=train_size)
        })
        test_df = pd.DataFrame({
            'id': test_ids,
            'category': test_categories,
            'target': rng.normal(loc=120.0 - case_num * 7.0, scale=25.0, size=test_size)
        })

        with tempfile.TemporaryDirectory() as tmpdir:
            train_csv = os.path.join(tmpdir, "train.csv")
            test_csv = os.path.join(tmpdir, "test.csv")
            train_df.to_csv(train_csv, index=False)
            test_df.to_csv(test_csv, index=False)

            run_cmd = [executable, "train.csv", "test.csv"]
            res = subprocess.run(run_cmd, cwd=tmpdir, capture_output=True, text=True, timeout=20)
            assert res.returncode == 0, f"Execution failed:\n{res.stderr}\n{res.stdout}"

            # Calculate the gold standard solely from training data.
            global_mean = train_df['target'].mean()
            cat_stats = train_df.groupby('category')['target'].agg(['count', 'mean'])
            m = 15.0
            cat_stats['gold_encoded'] = (
                cat_stats['count'] * cat_stats['mean'] + m * global_mean
            ) / (cat_stats['count'] + m)
            gold_map = cat_stats['gold_encoded'].to_dict()

            expected_train = gold_values(train_df, gold_map, global_mean)
            expected_test = gold_values(test_df, gold_map, global_mean)

            validate_output(os.path.join(tmpdir, "train_encoded.csv"),
                            train_df, expected_train)
            validate_output(os.path.join(tmpdir, "test_encoded.csv"),
                            test_df, expected_test)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
