#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak sox libsox-fmt-all ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /app/audio /app/metadata
    mkdir -p /home/user/chunks

    # Generate audio and log
    cat << 'EOF' > /tmp/setup_audio.py
import os
import subprocess

sentences = [
    "The quick brown fox",
    "jumps over the lazy dog",
    "and then it rained"
]

files = []
for i, text in enumerate(sentences):
    fname = f"/tmp/part{i}.wav"
    subprocess.run(["espeak", "-w", fname, text])
    files.append(fname)

    if i < len(sentences) - 1:
        nfname = f"/tmp/noise{i}.wav"
        subprocess.run(["sox", "-n", "-r", "22050", "-c", "1", nfname, "synth", "2", "pinknoise"])
        files.append(nfname)

subprocess.run(["sox"] + files + ["/app/audio/source.wav"])

log_content = ""
current_time = 0.0
record_id = 1

for f in files:
    dur = float(subprocess.check_output(["soxi", "-D", f]).strip())
    status = "Valid" if "part" in f else "Corrupt"

    log_content += f"Record ID: A{record_id}\n"
    log_content += f"Status: {status}\n"
    log_content += f"Start Time: {current_time:.3f}\n"
    log_content += f"End Time: {current_time + dur:.3f}\n"
    log_content += "---\n"

    current_time += dur
    record_id += 1

with open("/app/metadata/ingest.log", "w") as f:
    f.write(log_content)
EOF

    python3 /tmp/setup_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
