#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
import tempfile

def get_expected_ids():
    script = """
import pandas as pd
import numpy as np
import torch
import torch.nn as nn
from sklearn.metrics.pairwise import cosine_similarity

df = pd.read_csv('/home/user/raw_data.csv')
df['id'] = pd.to_numeric(df['id'], errors='coerce')
df = df.dropna(subset=['id'])
df['id'] = df['id'].astype(int)
df = df[df['category'].isin(['A', 'B', 'C'])]

feature_cols = [f'f{i}' for i in range(1, 11)]

for col in feature_cols:
    df[col] = df[col].fillna(df[col].median())

for col in feature_cols:
    mean = df[col].mean()
    std = df[col].std(ddof=1)
    df[col] = df[col].clip(lower=mean - 3*std, upper=mean + 3*std)

class Encoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(10, 8)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(8, 3)
    def forward(self, x):
        return self.fc2(self.relu(self.fc1(x)))

model = Encoder()
model.load_state_dict(torch.load('/home/user/encoder.pth'))
model.eval()

X = torch.FloatTensor(df[feature_cols].values)
with torch.no_grad():
    embeddings = model(X).numpy()

df_emb = pd.DataFrame(embeddings, index=df['id'])
target_emb = df_emb.loc[42].values.reshape(1, -1)
sims = cosine_similarity(target_emb, embeddings).flatten()

df['sim'] = sims
res = df[df['id'] != 42].sort_values('sim', ascending=False).head(5)
print(",".join(map(str, res['id'].tolist())))
"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(script)
        f_name = f.name

    try:
        output = subprocess.check_output([sys.executable, f_name], text=True)
        return [int(x.strip()) for x in output.strip().split(',')]
    finally:
        os.remove(f_name)

def test_recommendations_file_exists():
    path = '/home/user/recommendations.txt'
    assert os.path.exists(path), f"File {path} does not exist. The task requires writing the top 5 IDs to this file."
    assert os.path.isfile(path), f"Path {path} is not a file."

def test_recommendations_content():
    path = '/home/user/recommendations.txt'
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        lines = f.read().strip().splitlines()

    actual_ids = []
    for i, line in enumerate(lines):
        try:
            actual_ids.append(int(line.strip()))
        except ValueError:
            assert False, f"Line {i+1} in {path} is not a valid integer: '{line}'"

    assert len(actual_ids) == 5, f"Expected exactly 5 IDs in {path}, but found {len(actual_ids)}."

    expected_ids = get_expected_ids()
    assert actual_ids == expected_ids, f"The recommended IDs do not match the expected result. Expected {expected_ids}, but got {actual_ids}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
