#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest gTTS pydub pandas SpeechRecognition

    mkdir -p /app/bin

    # Generate audio file
    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
from pydub import AudioSegment

tts = gTTS("A T G C C G T A A C T G G", lang='en')
tts.save("/tmp/temp.mp3")

sound = AudioSegment.from_mp3("/tmp/temp.mp3")
sound.export("/app/sequence_audio.wav", format="wav")
EOF
    python3 /tmp/gen_audio.py

    # Create oracle
    cat << 'EOF' > /app/bin/oracle_score
#!/usr/bin/env python3
import sys

def score(seq1, seq2):
    total = 0
    for i in range(len(seq1) - 2):
        kmer = seq1[i:i+3]
        if kmer in seq2:
            total += 3
    total -= abs(len(seq1) - len(seq2))
    return total

if __name__ == '__main__':
    print(score(sys.argv[1], sys.argv[2]))
EOF
    chmod +x /app/bin/oracle_score

    # Create CSV
    cat << 'EOF' > /app/patient_reads.csv
sample_id,read_id,sequence
S01,R1,ATGCCGTAACTGG
S01,R2,ATGCCGTAAC
S02,R1,TTTAAA
S02,R3,ATGCCG
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
