#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg socat netcat-openbsd openssl gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create suspicious directory and binaries
    mkdir -p /home/user/suspicious
    echo 'echo "innocent"' > /home/user/suspicious/tool1
    echo 'echo "innocent 2"' > /home/user/suspicious/tool2
    echo 'bash -p' > /home/user/suspicious/pwn_bin

    # Create the access.log
    cat << 'EOF' > /home/user/access.log
10.0.0.1 - - [10/Oct/2023:13:55:36 -0700] "GET / HTTP/1.1" 200 2326
192.168.1.105 - - [10/Oct/2023:13:56:01 -0700] "GET /admin HTTP/1.1" 403 512
203.0.113.42 - - [10/Oct/2023:13:57:12 -0700] "GET /vulnerable_endpoint HTTP/1.1" 200 1024 "-" "Mozilla/5.0" "X-Exploit-Payload: true"
10.0.0.2 - - [10/Oct/2023:13:58:00 -0700] "POST /login HTTP/1.1" 401 128
EOF

    # Create the video artifact with a subtitle stream
    mkdir -p /app
    cat << 'EOF' > /tmp/sub.srt
1
00:00:00,000 --> 00:00:05,000
C2_SECRET: tr0ub4dour&3
EOF

    ffmpeg -f lavfi -i color=c=black:s=320x240:d=5 -i /tmp/sub.srt -c:v libx264 -c:s mov_text /app/evidence.mp4

    # Make home directory writable for the agent
    chmod -R 777 /home/user

    # Fix specific permissions required by the test
    chmod 755 /home/user/suspicious/tool1
    chmod 755 /home/user/suspicious/tool2
    chmod 4755 /home/user/suspicious/pwn_bin
