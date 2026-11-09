#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/projects/alpha/logs
    mkdir -p /home/user/projects/beta/logs

    cat << 'EOF' > /home/user/projects/config.json
{
  "projects": [
    {"name": "alpha", "log_dir": "/home/user/projects/alpha/logs"},
    {"name": "beta", "log_dir": "/home/user/projects/beta/logs"}
  ]
}
EOF

    echo "[LOG] 2023-10-01 System Initialized\nInitialization complete.\nReady." > /home/user/projects/alpha/logs/app.log
    printf '\xDE\xAD\xBE\xEF\x00\x01\x02\x03\x04' > /home/user/projects/alpha/logs/data.dat
    ln -s /home/user/projects/alpha/logs /home/user/projects/alpha/logs/recursive_loop

    echo "[LOG] 2023-10-02 Warning Encountered\nModule X failed to load.\nRetry attempt 1." > /home/user/projects/beta/logs/error.log
    printf '\xCA\xFE\xBA\xBE\xFF\xFF' > /home/user/projects/beta/logs/cache.dat
    ln -s /home/user/projects/alpha /home/user/projects/beta/logs/cross_link

    chown -R user:user /home/user/projects
    chmod -R 777 /home/user
