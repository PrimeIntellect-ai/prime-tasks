#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/raw_texts.txt
The quick brown fox jumps over the lazy dog.
A fast brown fox jumps over the lazy dog.
Data science involves extracting insights from data.
Extracting knowledge from data is what data science does.
I enjoy reading books about history.
Artificial intelligence will change the way we work.
AI is going to revolutionize our jobs.
I love reading historical books.
This is an entirely unique sentence.
EOF

chmod -R 777 /home/user
