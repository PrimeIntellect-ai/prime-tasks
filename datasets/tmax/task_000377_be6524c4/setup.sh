#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
pip3 install pytest

mkdir -p /app

espeak -w /app/research_memo.wav "To standardize our dataset embeddings for the new clustering model, we need to extract exactly three features. First, take the length of the dataset_name string. Second, take the num_rows and apply a floor division by 1000. Third, convert the is_public flag to an integer, so 1 for true and 0 for false. Output these three values in that exact order, separated by commas."

cat << 'EOF' > /app/oracle_encoder
#!/usr/bin/env python3
import sys
import json

def main():
    data = json.loads(sys.stdin.read())
    f1 = len(data['dataset_name'])
    f2 = data['num_rows'] // 1000
    f3 = 1 if data['is_public'] else 0
    print(f"{f1},{f2},{f3}")

if __name__ == "__main__":
    main()
EOF

chmod +x /app/oracle_encoder

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
