#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest networkx scipy numpy jupyter

    mkdir -p /app/corpus
    mkdir -p /app/verifier_corpus/clean
    mkdir -p /app/verifier_corpus/evil

    # Generate the audio file
    espeak -w /app/pi_instructions.wav "Hey, this is Dr. Smith. For the final network analysis, please compute the average clustering coefficient across all valid molecular graphs. Use exactly five thousand resamples for the bootstrap, and calculate the ninety-five percent confidence interval. Thanks."

    # Generate the graph datasets
    python3 -c '
import json
import os

def save_graph(path, atoms, bonds):
    with open(path, "w") as f:
        json.dump({"atoms": atoms, "bonds": bonds}, f)

clean1 = (
    [{"id": 0, "element": "O"}, {"id": 1, "element": "H"}, {"id": 2, "element": "H"}],
    [[0, 1], [0, 2]]
)
clean2 = (
    [{"id": 0, "element": "C"}, {"id": 1, "element": "H"}, {"id": 2, "element": "H"}, {"id": 3, "element": "H"}, {"id": 4, "element": "H"}],
    [[0, 1], [0, 2], [0, 3], [0, 4]]
)

evil1 = (
    [{"id": 0, "element": "C"}, {"id": 1, "element": "H"}, {"id": 2, "element": "H"}, {"id": 3, "element": "H"}, {"id": 4, "element": "H"}, {"id": 5, "element": "H"}],
    [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5]]
)
evil2 = (
    [{"id": 0, "element": "H"}, {"id": 1, "element": "C"}, {"id": 2, "element": "C"}],
    [[0, 1], [0, 2]]
)

save_graph("/app/corpus/clean1.json", *clean1)
save_graph("/app/corpus/evil1.json", *evil1)
save_graph("/app/verifier_corpus/clean/clean1.json", *clean1)
save_graph("/app/verifier_corpus/clean/clean2.json", *clean2)
save_graph("/app/verifier_corpus/evil/evil1.json", *evil1)
save_graph("/app/verifier_corpus/evil/evil2.json", *evil2)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
