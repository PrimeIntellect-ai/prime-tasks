#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean /home/user/drafts/sub1 /home/user/drafts/sub2

    espeak -w /app/voice_memo.wav "Attention team. We must scrub all documents. Any file containing the legacy code format which is the word PROJ hyphen followed by exactly three digits, another hyphen, and the uppercase letters X Y Z, must be flagged immediately and blocked from publication. Thank you."

    # Generate clean corpus
    echo "This is a clean doc with PROJ-123-ABC" > /app/corpus/clean/doc1.txt
    echo "Another clean one, just talking about XYZ" > /app/corpus/clean/doc2.txt
    echo "Normal documentation." > /app/corpus/clean/doc3.txt

    # Generate evil corpus
    echo "This leaked PROJ-999-XYZ in the text." > /app/corpus/evil/doc1.txt
    echo "PROJ-000-XYZ is our secret." > /app/corpus/evil/doc2.txt
    echo "Do not share PROJ-456-XYZ" > /app/corpus/evil/doc3.txt

    # Generate drafts for the agent to process
    echo "Draft 1 text" > /home/user/drafts/sub1/draft1.md
    echo "Draft 2 text with PROJ-111-XYZ" > /home/user/drafts/sub1/draft2.md
    echo "Draft 3 text" > /home/user/drafts/sub2/draft3.md
    touch -d "10 days ago" /home/user/drafts/sub1/draft1.md

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
