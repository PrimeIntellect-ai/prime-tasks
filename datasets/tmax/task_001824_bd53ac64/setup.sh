#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl sqlite3

    # Install common data science and web libraries that the agent might need
    pip3 install pytest flask fastapi uvicorn requests numpy scikit-learn

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the initial dataset
    python3 -c '
import json

data = [
    {"id": "doc1", "text": "Data science is the study of data to extract meaningful insights for business."},
    {"id": "doc2", "text": "Machine learning engineers build models to extract insights from massive data."},
    {"id": "doc3", "text": "Baking a chocolate cake requires flour, sugar, cocoa powder, and eggs."},
    {"id": "doc4", "text": "Data engineering involves building pipelines to store and transform data."},
    {"id": "doc5", "text": "The football match ended in a thrilling draw with both teams scoring two goals."},
    {"id": "doc6", "text": "Cloud computing provides on-demand availability of computer system resources, especially data storage."},
    {"id": "doc7", "text": "To make the perfect vanilla sponge cake, mix flour and sugar carefully."},
    {"id": "doc8", "text": "Deep learning is a subset of machine learning based on artificial neural networks."}
]

with open("/home/user/raw_data.jsonl", "w") as f:
    for item in data:
        f.write(json.dumps(item) + "\n")
'

    # Set permissions
    chmod -R 777 /home/user
