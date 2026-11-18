#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest pandas matplotlib jiwer

    mkdir -p /app
    espeak -w /app/interview.wav "Hello world. This is a test of the audio transcription pipeline."
    echo "hello world this is a test of the audio transcription pipeline" > /app/ground_truth.txt

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/plot_words.py
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib
# Misconfigured backend for headless environment
matplotlib.use('TkAgg')

def main():
    try:
        df = pd.read_csv('/home/user/dataset.csv', names=['filename', 'text'])
        # Basic tokenization
        words = df['text'].astype(str).str.lower().str.replace('[^\w\s]', '', regex=True).str.split(expand=True).stack().value_counts()

        plt.figure()
        words.head(10).plot(kind='bar')
        # Blocks in headless, prevents saving
        plt.show()
        plt.savefig('/home/user/word_freq.png')
    except Exception as e:
        print("Error:", e)

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
