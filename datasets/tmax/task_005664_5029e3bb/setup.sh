#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gzip
pip3 install pytest

mkdir -p /home/user/temp_docs
cd /home/user/temp_docs

# Create doc1 (30 lines) -> will not be split
for i in {1..30}; do echo "Line $i of intro document." >> intro.md; done

# Create doc2 (125 lines) -> split into part1 (50), part2 (50), part3 (25)
for i in {1..125}; do echo "Line $i of advanced guide." >> advanced_guide.md; done

# Create doc3 (50 lines) -> will not be split
for i in {1..50}; do echo "Line $i of api reference." >> api_reference.md; done

# Create doc4 (corrupted later? No, task says process valid archive)
for i in {1..10}; do echo "Line $i of notes." >> notes.txt; done # Note: .txt should be ignored

tar -czf /home/user/raw_docs.tar.gz *.md *.txt
cd /home/user
rm -rf /home/user/temp_docs

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
