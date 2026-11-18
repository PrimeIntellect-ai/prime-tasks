#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go tar zip
    pip3 install pytest

    mkdir -p /home/user/backups
    cd /home/user/backups

    # day1
    echo "version=1.0.0\nsetting=abc" > app.conf
    tar -czf day1.tar.gz app.conf
    rm app.conf

    # day2
    echo "version=1.1.0" > app.conf
    zip inner.zip app.conf
    tar -czf day2.tar.gz inner.zip
    rm app.conf inner.zip

    # day3
    touch app.conf
    zip level4.zip app.conf
    tar -czf level3.tar.gz level4.zip
    zip level2.zip level3.tar.gz
    tar -czf level1.tar.gz level2.zip
    tar -czf day3.tar.gz level1.tar.gz
    rm app.conf level4.zip level3.tar.gz level2.zip level1.tar.gz

    # config
    cat << 'EOF' > /home/user/config.json
{
  "backups": [
    {"name": "day1", "path": "/home/user/backups/day1.tar.gz"},
    {"name": "day2", "path": "/home/user/backups/day2.tar.gz"},
    {"name": "day3", "path": "/home/user/backups/day3.tar.gz"}
  ],
  "track_file": "app.conf",
  "max_depth": 3,
  "output": "/home/user/report.json"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
