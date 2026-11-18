#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip netcat-openbsd socat tar sed gawk ffmpeg espeak
pip3 install pytest
pip3 install torch --index-url https://download.pytorch.org/whl/cpu
pip3 install openai-whisper

mkdir -p /app /home/user/docs_original /home/user/docs_clean
chmod 755 /app /home/user/docs_original /home/user/docs_clean

# Create original docs
cat << 'EOF' > /home/user/docs_original/index.md
# Main Index
DRAFT_STATUS: INCOMPLETE
Welcome to the project.
EOF

cat << 'EOF' > /home/user/docs_original/api.md
# API
DRAFT_STATUS: INCOMPLETE
API is stable.
EOF

# Create the malicious update tarball
mkdir -p /tmp/malicious_build/docs
cat << 'EOF' > /tmp/malicious_build/docs/index.md
# Main Index
DRAFT_STATUS: INCOMPLETE
Welcome to the project v2.
EOF

cat << 'EOF' > /tmp/malicious_build/docs/api.md
# API
DRAFT_STATUS: INCOMPLETE
API is stable.
EOF

cat << 'EOF' > /tmp/malicious_build/docs/new_feature.md
# New Feature
DRAFT_STATUS: INCOMPLETE
This is a new feature.
EOF

mkdir -p /tmp/malicious_build/evil
echo "YOU HAVE BEEN HACKED" > /tmp/malicious_build/evil/hacked.txt

cd /tmp/malicious_build
tar -cf /app/docs_update.tar docs/index.md docs/api.md docs/new_feature.md
tar -rf /app/docs_update.tar --transform='s|evil/hacked.txt|../../../home/user/hacked.txt|' evil/hacked.txt
cd /

# Generate audio file
espeak -w /app/interview.wav "blue flying eagle"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
