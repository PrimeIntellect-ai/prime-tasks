#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app/audio
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the target.wav using python
    cat << 'EOF' > /tmp/gen_audio.py
import wave, math, struct
sample_rate = 8000
freq = 800

def generate_tone(duration_ms):
    num_samples = int(sample_rate * duration_ms / 1000.0)
    return [int(32767.0 * math.sin(2.0 * math.pi * freq * t / sample_rate)) for t in range(num_samples)]

def generate_silence(duration_ms):
    num_samples = int(sample_rate * duration_ms / 1000.0)
    return [0] * num_samples

morse = {'A': '.-', 'C': '-.-.', 'G': '--.', 'T': '-'}
dot = 100
dash = 300
intra_char = 100
inter_char = 300

seq = "ATGCGTACGTTAGCTAGCTAGCTA"
audio = []
for i, char in enumerate(seq):
    code = morse[char]
    for j, symbol in enumerate(code):
        if symbol == '.':
            audio.extend(generate_tone(dot))
        else:
            audio.extend(generate_tone(dash))
        if j < len(code) - 1:
            audio.extend(generate_silence(intra_char))
    if i < len(seq) - 1:
        audio.extend(generate_silence(inter_char))

with wave.open('/app/audio/target.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    for sample in audio:
        f.writeframesraw(struct.pack('<h', sample))
EOF
    python3 /tmp/gen_audio.py

    # Create clean corpus
    echo -n "CGTACGTTAG" > /app/corpus/clean/c1.txt

    # Create evil corpus
    echo -n "AAAA" > /app/corpus/evil/e1.txt
    echo -n "CGTACGTTAGC" > /app/corpus/evil/e2.txt
    echo -n "TGCGTACGTT" > /app/corpus/evil/e3.txt
    echo -n "GCGCGCGCGC" > /app/corpus/evil/e4.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
