#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ zlib1g-dev ffmpeg
    pip3 install pytest

    mkdir -p /app/configs/modules/a
    echo '{"app": "v1.0", "debug": true}' > /app/configs/main.json
    echo 'super_secret_key_123' > /app/configs/secrets.txt
    ln -s /app/configs/modules/a /app/configs/modules/a/loop

    ffmpeg -f lavfi -i color=c=blue:s=320x240:d=2 -c:v libx264 /app/config_history.mp4

    python3 -c "
import zlib
payload = b'CFGB' + zlib.compress(b'[{\"timestamp\": 1600000000, \"files\": [\"old.json\"]}]')
with open('/app/config_history.mp4', 'ab') as f:
    f.write(payload)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
