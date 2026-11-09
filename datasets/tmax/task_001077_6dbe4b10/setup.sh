#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_notes/tech/backend
    mkdir -p /home/user/raw_notes/personal
    mkdir -p /home/user/processed_notes

    cat << 'EOF' > /home/user/raw_notes/meeting1.md
# Project Kickoff

We discussed the new architecture for the file processor.
There are still some open questions.
EOF

    cat << 'EOF' > /home/user/raw_notes/tech/backend/api.md
# API v2 Documentation

Endpoints:
- /api/v2/users
- /api/v2/docs

This is a draft.
EOF

    cat << 'EOF' > /home/user/raw_notes/personal/todo.md
Buy milk
Review pull requests
Schedule dentist appointment
EOF

    cat << 'EOF' > /home/user/raw_notes/tech/notes.txt
# Random thoughts
This file should not be processed.
EOF

    chmod -R 777 /home/user
