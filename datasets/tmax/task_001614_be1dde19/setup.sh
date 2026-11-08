#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        jq \
        gawk \
        sed \
        coreutils

    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil /home/user

    cat << 'EOF' > /app/corpora/clean/1.jsonl
{"seq": 1, "text": "Welcome to the presentation."}
{"seq": 2, "text": "This is a valid Unicode check \u2713."}
EOF

    cat << 'EOF' > /app/corpora/evil/1.jsonl
{"seq": 1, "text": "Broken unicode \uD800 alone."}
EOF

    cat << 'EOF' > /app/corpora/evil/2.jsonl
{"seq": "abc", "text": "Bad seq type."}
EOF

    cat << 'EOF' > /home/user/raw_translations.jsonl
{"seq": 1, "text": "Slide 1: Introduction"}
{"seq": 999, "text": "Corrupt line \uZZZZ"}
{"seq": 2, "text": "Slide 2: Analytics"}
{"seq": 3, "text": "Slide 3: Deep Dive"}
{"seq": 4, "text": "Slide 4: Conclusion"}
EOF

    ffmpeg -f lavfi -i color=c=red:s=320x240:d=3.5 \
           -f lavfi -i color=c=blue:s=320x240:d=3.7 \
           -f lavfi -i color=c=green:s=320x240:d=6.9 \
           -f lavfi -i color=c=yellow:s=320x240:d=0.9 \
           -filter_complex "[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0[outv]" \
           -map "[outv]" -c:v libx264 -y /app/reference_ui.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
