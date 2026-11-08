#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr jq openssl xxd curl
    pip3 install pytest

    mkdir -p /app

    # Create dummy auth logs
    cat << 'EOF' > /app/auth_logs.json
[
  {
    "timestamp": "2023-10-24T10:00:00Z",
    "user_id": "victim",
    "action": "login",
    "status": "success",
    "debug_context": {
      "hmac_key": "s3cr3t_k3y_991"
    }
  }
]
EOF

    # Generate a video containing the leaked token
    # Using a simple white background with black text
    ffmpeg -f lavfi -i color=c=white:s=1280x720:d=1 -vf "drawtext=text='http\://attacker.com/?token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1c2VyIjoidmljdGltIiwiZXhwIjoxNjk4MDAwMDAwfQ.signature_here':fontsize=24:fontcolor=black:x=50:y=360" -c:v libx264 -y /app/capture.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
