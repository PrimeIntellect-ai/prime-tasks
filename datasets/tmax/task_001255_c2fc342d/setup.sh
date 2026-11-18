#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest pandas numpy SpeechRecognition pydub

    mkdir -p /app

    # Generate the instruction audio file
    espeak -w /app/instruction.wav "Subtract seventeen from all values."

    # Create the oracle pipeline
    cat << 'EOF' > /app/oracle_pipeline.py
#!/usr/bin/env python3
import sys
import pandas as pd
import numpy as np

def main():
    df = pd.read_csv(sys.stdin)
    if 'value' in df.columns:
        mean_val = np.floor(df['value'].mean())
        df['value'] = df['value'].fillna(mean_val)
        df['value'] = df['value'].astype(int)
        df['value'] = df['value'] - 17
    df.to_csv(sys.stdout, index=False)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_pipeline.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
