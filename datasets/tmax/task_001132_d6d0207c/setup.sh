#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil
    mkdir -p /app/test_corpora/clean /app/test_corpora/evil

    # Generate test video
    ffmpeg -f lavfi -i color=c=black:s=128x128:d=15 -r 1 -y /app/dataset_video.mp4

    # Create embed.py
    cat << 'EOF' > /app/embed.py
import sys

math_words = {"theorem", "proof", "integral", "matrix", "derivative", "vector", "space", "dimension", "linear", "algebra"}
conv_words = {"hello", "um", "students", "welcome", "today", "class", "so", "like", "okay", "guys"}

def get_embedding(text):
    words = text.lower().split()
    math_count = sum(1 for w in words if w in math_words)
    conv_count = sum(1 for w in words if w in conv_words)

    total = max(1, len(words))
    math_score = math_count / total
    conv_score = conv_count / total

    vec = [math_score]*5 + [conv_score]*5
    return " ".join(f"{x:.4f}" for x in vec)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    with open(sys.argv[1], 'r') as f:
        text = f.read()
    print(get_embedding(text))
EOF

    # Populate corpora
    for i in $(seq 1 10); do
        echo "theorem proof integral matrix derivative vector space linear algebra dimension" > /app/corpora/clean/file_$i.txt
        echo "hello um students welcome today class so like okay guys matrix" > /app/corpora/evil/file_$i.txt
    done

    for i in $(seq 1 20); do
        echo "theorem proof integral matrix derivative vector space linear algebra dimension" > /app/test_corpora/clean/file_$i.txt
        echo "hello um students welcome today class so like okay guys matrix" > /app/test_corpora/evil/file_$i.txt
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
