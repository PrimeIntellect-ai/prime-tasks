#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn pandas

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import json
import csv

os.makedirs("/home/user", exist_ok=True)

csv_data = [
    {"id": "A1", "title": "Quantum Computing", "abstract": "Quantum computers use qubits to perform complex computations."},
    {"id": "A2", "title": "Machine Learning", "abstract": "Deep learning models require large amounts of data to train."},
    {"id": "A3", "title": "Space Exploration", "abstract": "Mars rovers collect soil samples for scientific analysis."}
]

json_data = [
    {"doc_id": "B10", "text": "Deep neural networks are trained on big data for AI tasks."},
    {"doc_id": "B11", "text": "NASA sends rovers to the red planet to analyze dirt and soil."},
    {"doc_id": "B12", "text": "Qubits are the fundamental unit of quantum algorithms and complex computations."}
]

with open("/home/user/dataset_A.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["id", "title", "abstract"])
    writer.writeheader()
    for row in csv_data:
        writer.writerow(row)

with open("/home/user/dataset_B.json", "w") as f:
    json.dump(json_data, f, indent=2)
'

    chmod -R 777 /home/user
