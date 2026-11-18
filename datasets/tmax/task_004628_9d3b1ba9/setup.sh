#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest

mkdir -p /app
# Generate a dummy 3-minute video so the agent can extract frames
ffmpeg -f lavfi -i color=c=blue:s=320x240:d=180 -c:v libx264 /app/tutorial.mp4

mkdir -p /home/user/docs/images
mkdir -p /app/corpus/evil
mkdir -p /app/corpus/clean

cat << 'EOF' > /home/user/metadata.json
{
  "tutorial_name": "Setup Guide",
  "extract_frames": [
    "00:00:15",
    "00:01:23",
    "00:02:45"
  ]
}
EOF

cat << 'EOF' > /app/corpus/evil/draft1.md
# API Guide
Connect to api.internal.corp:8080/v2 for testing.
EOF

cat << 'EOF' > /app/corpus/evil/draft2.md
# Credentials
Use test_user_admin:A1b2C3d4E5f6 for the DB.
EOF

cat << 'EOF' > /app/corpus/evil/draft3.md
Multiple leaks: api.internal.corp:8080/v9 and test_user_dev:1234567890ab.
EOF

cat << 'EOF' > /app/corpus/clean/pub1.md
# API Guide
Connect to api.public.com/v2 for production.
EOF

cat << 'EOF' > /app/corpus/clean/pub2.md
# Credentials
Use test_user_admin:short for the DB. (Notice password is not 12 characters).
EOF

cat << 'EOF' > /app/corpus/clean/pub3.md
Also safe: api.internal.corp:8080/v10 (v10 is two digits, rule specifies v1-9).
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
