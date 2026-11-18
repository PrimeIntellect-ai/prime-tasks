#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import json
import csv
import math

os.makedirs("/home/user/etl_data", exist_ok=True)
os.makedirs("/home/user/model", exist_ok=True)

vocab = {
    "data": [1.0, 0.2, -0.5, 0.0, 0.1],
    "engineer": [0.5, 0.8, 0.1, -0.2, 0.0],
    "pipeline": [0.0, 1.0, 0.5, 0.5, -0.5],
    "model": [0.2, -0.2, 0.8, 1.0, 0.2],
    "inference": [-0.5, 0.0, 0.0, 0.8, 1.0],
    "retrieval": [0.8, 0.2, -0.2, 0.1, 0.5],
    "system": [0.1, 0.1, 0.1, 0.1, 0.1],
    "golang": [1.0, 1.0, 1.0, 1.0, 1.0],
    "cloud": [-0.5, -0.5, 0.5, 0.5, 0.0],
    "scale": [0.0, 0.0, 0.0, -1.0, -1.0]
}

with open("/home/user/model/vocab.json", "w") as f:
    json.dump(vocab, f)

projection = [
    [0.5, -0.2],
    [0.1, 0.8],
    [-0.3, 0.4],
    [0.9, -0.1],
    [0.2, 0.5]
]

with open("/home/user/model/projection.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(projection)

docs = {
    "doc01.txt": "data engineer data pipeline",
    "doc02.txt": "model inference model system",
    "doc03.txt": "retrieval system golang",
    "doc04.txt": "cloud scale system",
    "doc05.txt": "data model retrieval",
    "doc06.txt": "engineer cloud golang pipeline",
    "doc07.txt": "inference scale system data",
    "doc08.txt": "golang golang golang",
    "doc09.txt": "unknown words should be ignored completely system",
    "doc10.txt": "data engineer model inference retrieval pipeline system golang cloud scale"
}

for name, content in docs.items():
    with open(f"/home/user/etl_data/{name}", "w") as f:
        f.write(content)

query = [0.85, -0.15]
results = []

for name, content in docs.items():
    words = content.split()
    known_words = [w for w in words if w in vocab]

    if not known_words:
        doc_emb = [0.0]*5
    else:
        doc_emb = [0.0]*5
        for w in known_words:
            for i in range(5):
                doc_emb[i] += vocab[w][i]
        doc_emb = [x/len(known_words) for x in doc_emb]

    reduced = [0.0, 0.0]
    for j in range(2):
        for i in range(5):
            reduced[j] += doc_emb[i] * projection[i][j]

    dist = math.sqrt((reduced[0] - query[0])**2 + (reduced[1] - query[1])**2)
    results.append((dist, name))

results.sort(key=lambda x: (x[0], x[1]))

with open("/home/user/.truth.txt", "w") as f:
    for i in range(3):
        f.write(results[i][1] + "\n")
'

    chmod -R 777 /home/user
