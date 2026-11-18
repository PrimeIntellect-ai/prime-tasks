#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the dataset_metadata directory and populate it
    mkdir -p /home/user/dataset_metadata

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs('/home/user/dataset_metadata', exist_ok=True)

datasets = {
    "dataset_01.txt": "A large collection of chest X-ray images with bounding boxes for pneumonia and other thoracic diseases.",
    "dataset_02.txt": "Stock market prices for the S&P 500 over the last 10 years, including open, close, high, low.",
    "dataset_03.txt": "MRI scans of the human brain for tumor detection.",
    "dataset_04.txt": "Text corpus of Wikipedia articles translated into 50 languages.",
    "dataset_05.txt": "De-identified electronic health records containing patient diagnoses and lab results.",
    "dataset_06.txt": "High-resolution satellite imagery for land cover classification.",
    "dataset_07.txt": "Audio recordings of common bird species from the Amazon rainforest.",
    "dataset_08.txt": "CT scans of the lungs for detecting COVID-19 and severe pneumonia.",
    "dataset_09.txt": "Customer reviews for electronics from a large e-commerce platform.",
    "dataset_10.txt": "Annotated bounding boxes for self-driving cars, including pedestrians, vehicles, and traffic lights."
}

for filename, content in datasets.items():
    with open(f"/home/user/dataset_metadata/{filename}", "w") as f:
        f.write(content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
