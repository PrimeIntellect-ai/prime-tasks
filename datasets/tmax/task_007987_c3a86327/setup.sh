#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/dataset.jsonl
{"id": "doc1", "text": "This is a simple test document for tokenization."}
{"id": "doc2", "text": "Artificial intelligence and machine learning are revolutionizing the way we process data. Experiment tracking is critical."}
{"id": "doc3", "text": "Short text."}
{"id": "doc4", "text": "Inference performance benchmarking requires careful setup of the analysis environment, precise package installation, and systematic experiment tracking to ensure reproducible results across different hardware configurations."}
{"id": "doc5", "text": "Data science is fun!"}
{"id": "doc6", "text": "Another document with some random words to tokenize and count."}
{"id": "doc7", "text": "To be or not to be, that is the question that many philosophers have pondered over the centuries."}
{"id": "doc8", "text": "Python is a high-level, general-purpose programming language. Its design philosophy emphasizes code readability."}
{"id": "doc9", "text": "Tokenization breaks raw text into words, symbols, or elements called tokens."}
{"id": "doc10", "text": "The quick brown fox jumps over the lazy dog repeatedly while researchers organize datasets."}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
