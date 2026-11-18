#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak curl
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "Hello build engineer. The new emergency proxy token is delta niner whiskey two. I repeat, delta niner whiskey two."

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mobile_graph.json
{
  "App": ["UI", "Core"],
  "UI": ["Core", "Assets"],
  "Core": ["Network", "Database"],
  "Assets": [],
  "Network": ["Utils"],
  "Database": ["Utils"],
  "Utils": []
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
