#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import numpy as np
import pandas as pd
import torch
import torchvision.transforms as T
from torchvision.models import resnet18
from PIL import Image

def generate_ground_truth():
    os.makedirs("/tmp/gt_frames", exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-i", "/app/data.mp4", "-vf", "fps=1", "/tmp/gt_frames/frame_%04d.jpg"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    frames = sorted(os.listdir("/tmp/gt_frames"))
    if not frames:
        raise ValueError("No frames extracted from /app/data.mp4.")

    model = resnet18(pretrained=True)
    model = torch.nn.Sequential(*list(model.children())[:-1])
    model.eval()

    transform = T.Compose([
        T.Resize((224, 224)),
        T.ToTensor(),
        T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    embeddings = []
    for f in frames:
        img = Image.open(os.path.join("/tmp/gt_frames", f)).convert("RGB")
        tensor = transform(img).unsqueeze(0)
        with torch.no_grad():
            feat = model(tensor).flatten().numpy()
        embeddings.append(feat)

    embeddings = np.array(embeddings)

    target_idx = frames.index("frame_0015.jpg")
    target_emb = embeddings[target_idx]

    def cosine_sim(a, b):
        return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))

    sims = np.array([cosine_sim(e, target_emb) for e in embeddings])

    N = len(frames)
    L1 = np.exp(5 * sims)
    L0 = np.exp(2.0 * np.ones(N))

    A = np.array([[0.95, 0.05],
                  [0.10, 0.90]])

    alpha = np.zeros((N, 2))
    alpha[0, 0] = 0.9 * L0[0]
    alpha[0, 1] = 0.1 * L1[0]
    alpha[0] /= np.sum(alpha[0])

    for t in range(1, N):
        alpha[t, 0] = L0[t] * (alpha[t-1, 0] * A[0, 0] + alpha[t-1, 1] * A[1, 0])
        alpha[t, 1] = L1[t] * (alpha[t-1, 0] * A[0, 1] + alpha[t-1, 1] * A[1, 1])
        alpha[t] /= np.sum(alpha[t])

    beta = np.zeros((N, 2))
    beta[-1] = 1.0
    for t in range(N-2, -1, -1):
        beta[t, 0] = A[0, 0] * L0[t+1] * beta[t+1, 0] + A[0, 1] * L1[t+1] * beta[t+1, 1]
        beta[t, 1] = A[1, 0] * L0[t+1] * beta[t+1, 0] + A[1, 1] * L1[t+1] * beta[t+1, 1]
        beta[t] /= np.sum(beta[t])

    gamma = alpha * beta
    gamma = gamma / np.sum(gamma, axis=1, keepdims=True)

    posteriors = gamma[:, 1]

    return pd.DataFrame({'frame_name': frames, 'gt_prob': posteriors})


def test_posterior_probabilities():
    agent_file = "/home/user/posteriors.csv"
    assert os.path.exists(agent_file), f"Output file {agent_file} not found."

    try:
        agent_df = pd.read_csv(agent_file)
    except Exception as e:
        assert False, f"Failed to read {agent_file} as a CSV: {e}"

    assert 'frame_name' in agent_df.columns, "CSV missing 'frame_name' column."
    assert 'posterior_prob' in agent_df.columns, "CSV missing 'posterior_prob' column."

    gt_df = generate_ground_truth()

    assert agent_df['frame_name'].is_unique, "CSV contains duplicate frame names."
    assert len(agent_df) == len(gt_df), f"Row count mismatch. Expected {len(gt_df)}, got {len(agent_df)}"
    assert set(agent_df['frame_name']) == set(gt_df['frame_name']), "CSV frame names do not exactly cover all extracted frames."

    merged = pd.merge(gt_df, agent_df, on='frame_name', how='inner')
    assert len(merged) == len(gt_df), f"Row count mismatch. Expected {len(gt_df)}, got {len(merged)}"

    mae = np.mean(np.abs(merged['gt_prob'] - merged['posterior_prob']))

    threshold = 0.02
    assert mae <= threshold, f"MAE {mae:.4f} exceeds the threshold of {threshold}. The computed probabilities are too far from the ground truth."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
