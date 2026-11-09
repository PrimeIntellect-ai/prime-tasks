#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg coreutils
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

# Generate audio fixture
espeak -w /app/architect_memo.wav "Hello. To unpack our new documentation format, first reverse the file byte by byte, and then base64 decode it. Legitimate files will always begin with the exact string 'TECHDOC-V1'. Make sure you use flock to update the master index concurrently."

# Create Clean files
echo -n "TECHDOC-V1: System Architecture" | base64 | tac -rs . > /app/corpus/clean/doc1.bin
echo -n "TECHDOC-V1: API Endpoints" | base64 | tac -rs . > /app/corpus/clean/doc2.bin
echo -n "TECHDOC-V1: Deployment Guide" | base64 | tac -rs . > /app/corpus/clean/doc3.bin

# Create Evil files
# 1. Missing signature
echo -n "FAKEDOC: Malicious payload" | base64 | tac -rs . > /app/corpus/evil/fake1.bin
# 2. Not reversed
echo -n "TECHDOC-V1: Unreversed" | base64 > /app/corpus/evil/fake2.bin
# 3. Symlink loop
ln -s /app/corpus/evil/loop.bin /app/corpus/evil/loop.bin
# 4. Standard text file (will fail base64 decode or signature check)
echo "TECHDOC-V1: Just raw text, not encoded" > /app/corpus/evil/fake3.bin

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
