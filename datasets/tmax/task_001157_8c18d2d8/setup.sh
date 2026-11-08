#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential git wget
pip3 install pytest pandas numpy

mkdir -p /app
cd /app
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git whisper
wget -q -O ggml-tiny.en.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin
cp whisper/samples/jfk.wav interview.wav

cat << 'EOF' > /tmp/verify.py
import pandas as pd
import sys
import numpy as np

def verify():
    try:
        df_agent = pd.read_csv('/home/user/dataset.tsv', sep='\t')
        expected_cols = ['segment_id', 'start_ms', 'end_ms', 'duration_ms', 'transcript']
        if not all(c in df_agent.columns for c in expected_cols):
            print("Missing columns")
            sys.exit(1)
        expected_duration = df_agent['end_ms'].astype(float) - df_agent['start_ms'].astype(float)
        actual_duration = df_agent['duration_ms'].astype(float)
        mae = np.mean(np.abs(expected_duration - actual_duration))
        if df_agent['duration_ms'].isna().any() or df_agent['transcript'].isna().any():
            mae += 9999.0
        print(f"MAE: {mae}")
    except Exception as e:
        print(f"MAE: 9999.0")
        sys.exit(1)

if __name__ == "__main__":
    verify()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
