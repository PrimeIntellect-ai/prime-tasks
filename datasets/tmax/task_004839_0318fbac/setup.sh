#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest pandas gTTS

    # Install torch CPU to save time, then whisper
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install openai-whisper

    mkdir -p /app

    # Generate audio file
    cat << 'EOF' > /app/gen_audio.py
from gtts import gTTS
import os

text = "Customer one is François from Paris, age 34. Customer two is test89 from Berlin, age 45. Customer three is Müller from München, age 29. Customer four is Alice from London, age 16."
tts = gTTS(text=text, lang='en')
tts.save("/app/field_dictation.mp3")
os.system("ffmpeg -i /app/field_dictation.mp3 /app/field_dictation.wav -y")
os.remove("/app/field_dictation.mp3")
EOF
    python3 /app/gen_audio.py

    # Create legacy_records.csv
    cat << 'EOF' > /app/legacy_records.csv
Name,City,Age
John Doe,New York,45
Jane Smith,LosAngeles123,30
Bob,Chicago,15
Alice,Seattle,125
Valid User,Boston,50
EOF

    # Create ground_truth.csv
    cat << 'EOF' > /app/ground_truth.csv
Name,City,Age
John Doe,New York,45
Valid User,Boston,50
François,Paris,34
test89,Berlin,45
Müller,München,29
EOF

    # Create verify.py
    cat << 'EOF' > /app/verify.py
import pandas as pd
import sys

def compute_f1():
    try:
        truth = pd.read_csv('/app/ground_truth.csv')
        pred = pd.read_csv('/home/user/clean_merged.csv')
    except Exception as e:
        print("Accuracy: 0.0")
        return

    # Convert to sets of tuples
    truth_set = set(tuple(str(i) for i in x) for x in truth.to_records(index=False))
    pred_set = set(tuple(str(i) for i in x) for x in pred.to_records(index=False))

    intersection = truth_set.intersection(pred_set)
    if len(pred_set) == 0:
        f1 = 0.0
    else:
        precision = len(intersection) / len(pred_set)
        recall = len(intersection) / len(truth_set)
        if precision + recall == 0:
            f1 = 0.0
        else:
            f1 = 2 * (precision * recall) / (precision + recall)

    print(f"Accuracy: {f1}")

if __name__ == "__main__":
    compute_f1()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
