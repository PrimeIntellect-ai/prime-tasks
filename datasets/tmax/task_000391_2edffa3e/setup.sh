#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg rustc cargo fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create video file with the required text
    ffmpeg -f lavfi -i color=c=black:s=800x400:d=2 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='CONFIG\: PORT=8443 | COOKIE_PREFIX=X-RT- | CSP_ALLOW=https\://assets.internal.net':fontcolor=white:fontsize=20:x=(w-text_w)/2:y=(h-text_h)/2" -c:v libx264 -t 2 /app/intercept_leak.mp4

    # Create clean corpus files
    cat << 'EOF' > /app/corpora/clean/req1.json
{
  "target_port": 8443,
  "headers": {
    "Cookie": "AuthToken=X-RT-12345",
    "Content-Security-Policy": "script-src 'self' https://assets.internal.net"
  },
  "body": "..."
}
EOF

    cat << 'EOF' > /app/corpora/clean/req2.json
{
  "target_port": 8443,
  "headers": {
    "Cookie": "AuthToken=X-RT-abc",
    "Content-Security-Policy": "script-src 'self'"
  },
  "body": "..."
}
EOF

    # Create evil corpus files
    cat << 'EOF' > /app/corpora/evil/req1.json
{
  "target_port": 8080,
  "headers": {
    "Cookie": "AuthToken=X-RT-12345",
    "Content-Security-Policy": "script-src 'self' https://assets.internal.net"
  },
  "body": "..."
}
EOF

    cat << 'EOF' > /app/corpora/evil/req2.json
{
  "target_port": 8443,
  "headers": {
    "Cookie": "AuthToken=Y-RT-12345",
    "Content-Security-Policy": "script-src 'self' https://assets.internal.net"
  },
  "body": "..."
}
EOF

    cat << 'EOF' > /app/corpora/evil/req3.json
{
  "target_port": 8443,
  "headers": {
    "Cookie": "AuthToken=X-RT-12345",
    "Content-Security-Policy": "script-src 'self' https://evil.com"
  },
  "body": "..."
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
