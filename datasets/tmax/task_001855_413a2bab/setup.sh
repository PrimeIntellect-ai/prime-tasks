#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app

    # Create Python script to generate DTMF
    cat << 'EOF' > /tmp/gen_dtmf.py
import wave, math, struct

def generate_tone(f1, f2, duration, sample_rate=8000):
    samples = []
    for i in range(int(sample_rate * duration)):
        t = float(i) / sample_rate
        val = math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)
        samples.append(int(val * 16383))
    return samples

dtmf_freqs = {
    '8': (852, 1336),
    '4': (770, 1209),
    '9': (852, 1477),
    '2': (697, 1336)
}

digits = "8492"
all_samples = []
for d in digits:
    f1, f2 = dtmf_freqs[d]
    all_samples.extend(generate_tone(f1, f2, 0.5))
    all_samples.extend([0]*4000) # pause

with wave.open('/app/sequence_signal.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(8000)
    for s in all_samples:
        w.writeframesraw(struct.pack('<h', s))
EOF
    python3 /tmp/gen_dtmf.py

    # Create database.fasta
    cat << 'EOF' > /app/database.fasta
>seq_1111
ATGC
>seq_8492
ATGCGTACGTTAGC
>seq_2222
CGTA
EOF

    # Create queries.fasta
    cat << 'EOF' > /app/queries.fasta
>query_1
ATGC
>query_14
ATGCGTACGTTAGA
>query_2
CGTA
EOF

    # Create aligner.c
    cat << 'EOF' > /app/aligner.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    char *s1 = argv[1];
    char *s2 = argv[2];
    int score = 0;
    for (int i = 0; s1[i] && s2[i]; i++) {
        if (s1[i] == s2[i]) score += 3;
        else score -= 1;
    }
    printf("%d\n", score);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
