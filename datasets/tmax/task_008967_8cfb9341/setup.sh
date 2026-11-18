#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np
import os
import json
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.metrics.pairwise import cosine_similarity

np.random.seed(42)

# Generate features
n_tracks = 200
track_ids = [f"track_{i:03d}" for i in range(n_tracks)]
features_df = pd.DataFrame({
    "track_id": track_ids,
    "acousticness": np.random.uniform(0, 1, n_tracks),
    "danceability": np.random.uniform(0, 1, n_tracks),
    "energy": np.random.uniform(0, 1, n_tracks),
    "instrumentalness": np.random.uniform(0, 1, n_tracks),
    "tempo": np.random.uniform(60, 180, n_tracks)
})

# Generate metadata
genres = ["rock", "electronic", "pop", "jazz", "classical"]
metadata_df = pd.DataFrame({
    "track_id": track_ids,
    "genre": np.random.choice(genres, n_tracks)
})

# Generate history
history_records = []
users = [f"user_{i:02d}" for i in range(50)]
# Force user_42 to like high energy, high tempo
user_42_tracks = features_df[(features_df["energy"] > 0.8) & (features_df["tempo"] > 140)]["track_id"].tolist()
np.random.shuffle(user_42_tracks)
user_42_listened = user_42_tracks[:10]

for u in users:
    n_listens = np.random.randint(5, 20)
    if u == "user_42":
        u_tracks = user_42_listened
        counts = np.random.randint(5, 50, len(u_tracks))
    else:
        u_tracks = np.random.choice(track_ids, n_listens, replace=False)
        counts = np.random.randint(1, 20, n_listens)

    for t, c in zip(u_tracks, counts):
        history_records.append({"user_id": u, "track_id": t, "play_count": c})

history_df = pd.DataFrame(history_records)

features_df.to_csv("/home/user/data/features.csv", index=False)
metadata_df.to_csv("/home/user/data/metadata.csv", index=False)
history_df.to_csv("/home/user/data/history.csv", index=False)

# Ground truth calculation to verify consistency
feature_cols = ["acousticness", "danceability", "energy", "instrumentalness", "tempo"]

# 1. User profile
u42_hist = history_df[history_df["user_id"] == "user_42"]
u42_data = pd.merge(u42_hist, features_df, on="track_id")
weights = u42_data["play_count"].values
profile = np.average(u42_data[feature_cols].values, axis=0, weights=weights).reshape(1, -1)

# 2. Filter Candidates
listened = set(u42_hist["track_id"])
candidates = metadata_df[(metadata_df["genre"] == "electronic") & (~metadata_df["track_id"].isin(listened))]
cand_data = pd.merge(candidates, features_df, on="track_id")

# 3. Dimensionality Reduction
scaler = StandardScaler()
scaled_all = scaler.fit_transform(features_df[feature_cols])
pca = PCA(n_components=2, random_state=42)
pca.fit(scaled_all)

# 4. Transform & Similarity
profile_2d = pca.transform(scaler.transform(profile))
cand_features_2d = pca.transform(scaler.transform(cand_data[feature_cols]))

sims = cosine_similarity(profile_2d, cand_features_2d)[0]
cand_data["sim"] = sims

# 5. Output
top_3 = cand_data.sort_values(by=["sim", "track_id"], ascending=[False, True]).head(3)["track_id"].tolist()

with open("/home/user/ground_truth.json", "w") as f:
    json.dump({"user_42": top_3}, f)
EOF

    python3 /home/user/setup_data.py

    chmod -R 777 /home/user
