#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest openai-whisper

    mkdir -p /app/dataset
    mkdir -p /app/bin

    # Create a dummy valid WAV file
    python3 -c "
import wave, struct
with wave.open('/app/dataset/interview.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(16000)
    f.writeframesraw(struct.pack('<h', 0) * 16000)
"

    cat << 'EOF' > /app/bin/oracle_tfidf
#!/usr/bin/env python3
import sys, math
from collections import defaultdict

def main():
    N = 0
    df = defaultdict(int)
    for line in sys.stdin:
        line = line.strip()
        tokens = line.lower().split()
        if not tokens:
            print("0.0000")
            continue

        N += 1
        unique_tokens = set(tokens)
        for t in unique_tokens:
            df[t] += 1

        l2_sq = 0.0
        doc_len = len(tokens)

        tf_counts = defaultdict(int)
        for t in tokens:
            tf_counts[t] += 1

        for t in unique_tokens:
            tf = tf_counts[t] / doc_len
            idf = math.log(N / df[t]) + 1.0
            tfidf = tf * idf
            l2_sq += tfidf * tfidf

        l2 = math.sqrt(l2_sq)
        print(f"{l2:.4f}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/bin/oracle_tfidf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
