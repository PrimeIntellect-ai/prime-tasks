#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip systemd logrotate
    pip3 install pytest jiwer

    # Install CPU-only torch to save build time and prevent timeouts
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install openai-whisper

    # Create required directories and files
    mkdir -p /app
    echo "dummy wav content" > /app/voicemail.wav

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/.config/systemd/user

    cat << 'EOF' > /home/user/transcribe.sh
#!/bin/bash
# Buggy script
mkdir -p /var/log/transcriber
whisper /app/voicemail.wav --output_dir /var/log/transcriber/
EOF
    chmod +x /home/user/transcribe.sh

    cat << 'EOF' > /home/user/.config/systemd/user/voicemail-transcriber.service
[Unit]
Description=Voicemail Transcriber

[Service]
ExecStart=/home/user/transcribe.sh
Restart=always
RestartSec=0
StandardOutput=file:/var/log/transcriber/service.log

[Install]
WantedBy=default.target
EOF

    # Overwrite whisper with a mock to avoid running heavy models on dummy audio
    cat << 'EOF' > /usr/local/bin/whisper
#!/usr/bin/env python3
import argparse
import os

parser = argparse.ArgumentParser()
parser.add_argument("audio", nargs="+")
parser.add_argument("--output_dir", "-o", default=".")
args, _ = parser.parse_known_args()

text = "hello this is john from accounting i am calling to remind you about the budget meeting tomorrow at ten am please bring the q3 reports thank you"

for audio in args.audio:
    base = os.path.splitext(os.path.basename(audio))[0]
    out_path = os.path.join(args.output_dir, base + ".txt")
    with open(out_path, "w") as f:
        f.write(text + "\n")
EOF
    chmod +x /usr/local/bin/whisper

    chown -R user:user /home/user
    chmod -R 777 /home/user
