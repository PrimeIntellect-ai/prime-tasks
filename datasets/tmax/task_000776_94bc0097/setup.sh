#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/dataset_info

    cat << 'EOF' > /home/user/setup_data.py
import csv
import random
import os

random.seed(42)

descriptions = [
    "A large-scale dataset of autonomous driving trajectories.",
    "Medical imaging dataset containing annotated X-rays.",
    "Text corpus for natural language processing of legal documents.",
    "High-resolution satellite imagery for agriculture.",
    "Financial time-series data for stock market prediction.",
    "Dataset of user interactions on a major e-commerce platform.",
    "Audio recordings of various bird species for ecological studies.",
    "Synthetic data for training reinforcement learning agents in robotics.",
    "Collection of historical weather records spanning a century.",
    "Genomic sequences of rare plant species.",
    "Dataset for pedestrian detection in urban environments.",
    "MRI scans with expert segmentations of brain tumors.",
    "Bilingual sentence pairs for machine translation.",
    "Multispectral drone imagery for crop health monitoring.",
    "Cryptocurrency transaction graph data.",
    "Clickstream data from a network of news websites.",
    "Acoustic signatures of marine mammals.",
    "Simulation logs of robotic arm manipulation tasks.",
    "Hourly climate metrics from global weather stations.",
    "Protein structure data for drug discovery."
]

os.makedirs("/home/user/dataset_info", exist_ok=True)

with open("/home/user/dataset_info/metadata.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["dataset_id", "year_created"])
    for i, desc in enumerate(descriptions):
        with open(f"/home/user/dataset_info/dataset_{i}.txt", "w") as df:
            df.write(desc)

        year = random.randint(2010, 2023)
        writer.writerow([f"dataset_{i}", year])
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
