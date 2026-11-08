#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/drafts
    mkdir -p /home/user/final_docs

    cat << 'EOF' > /home/user/setup_drafts.py
import gzip
import os

drafts = {
    "draft_001.txt.gz": "TITLE: API Reference v2\n",
    "draft_002.txt.gz": "TITLE: User Guide 2023!\n",
    "draft_003.txt.gz": "TITLE: Troubleshooting Network \n",
    "draft_004.txt.gz": "TITLE: Architecture Overview\n",
    "draft_005.txt.gz": "TITLE: Getting Started: Intro\n",
}

for filename, title_line in drafts.items():
    filepath = os.path.join('/home/user/drafts', filename)
    with gzip.open(filepath, 'wt') as f:
        # Add some dummy padding
        for _ in range(50):
            f.write("Some dummy text for the documentation draft. " * 20 + "\n")
        f.write(title_line)
        for _ in range(5000): # Pad to make it "large"
            f.write("More documentation content here. " * 20 + "\n")
EOF
    python3 /home/user/setup_drafts.py
    rm /home/user/setup_drafts.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
