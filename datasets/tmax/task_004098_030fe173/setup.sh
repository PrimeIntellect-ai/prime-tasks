#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go espeak
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate audio file
    espeak -w /app/voicenote.wav "Reject any dataset where the Pearson correlation between token count and latency is strictly less than zero."

    # Generate TSV files
    python3 -c "
import os

clean_data = 'shard_id\ttoken_count\tlatency_ms\n1\t10\t100\n2\t20\t200\n3\t30\t300\n'
evil_data = 'shard_id\ttoken_count\tlatency_ms\n1\t10\t300\n2\t20\t200\n3\t30\t100\n'

for i in range(2):
    with open(f'/app/corpora/clean/clean_{i}.tsv', 'w') as f:
        f.write(clean_data)
    with open(f'/app/corpora/evil/evil_{i}.tsv', 'w') as f:
        f.write(evil_data)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
