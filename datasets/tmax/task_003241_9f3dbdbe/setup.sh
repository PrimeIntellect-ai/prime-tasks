#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr cron
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/app
    mkdir -p /app

    # Generate config_snapshot.png
    convert -size 400x200 xc:white -fill black -pointsize 16 -draw "text 10,50 'UPSTREAM_TARGET_HOST=127.0.0.55\nUPSTREAM_TARGET_PORT=9090'" /app/config_snapshot.png

    # Create config.json
    cat << 'EOF' > /home/user/app/config.json
{"host": "", "port": 0}
EOF

    # Create auth.json
    cat << 'EOF' > /home/user/app/auth.json
{"users": {"admin": {"groups": ["wheel"]}}}
EOF

    # Create daemon.py
    cat << 'EOF' > /home/user/app/daemon.py
def startup_check():
    list1 = list(range(10000))
    list2 = list(range(10000))
    res = 0
    for x in list1:
        for y in list2:
            if x == y and x < 100:
                res += x
    return res
EOF

    # Create health_ping.py
    cat << 'EOF' > /home/user/app/health_ping.py
#!/usr/bin/env python3
print("pong")
EOF
    chmod +x /home/user/app/health_ping.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
