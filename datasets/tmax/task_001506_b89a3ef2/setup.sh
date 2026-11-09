#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gawk sed libc-bin wget procps
    pip3 install pytest

    mkdir -p /var/www
    cd /var/www

    cat << 'EOF' > raw_logs_temp.csv
id,timestamp,status,message
1,12/31/2023 23:59:59,200,"System started successfully"
2,01/01/2024 00:01:00,404,"Page not found"
3,01/01/2024 00:02:00,500,"Error in module:
Null pointer exception"
4,01/01/2024 00:03:00,999,"Invalid status"
6,01/01/2024 00:05:00,301,"Redirecting..."
EOF

    echo -e '5,01/01/2024 00:04:00,200,"Garbage data \xff\xfe here"' >> raw_logs_temp.csv
    mv raw_logs_temp.csv raw_logs.csv

    useradd -m -s /bin/bash user || true

    # Ensure the HTTP server runs when a shell is opened
    echo 'if ! pgrep -f "http.server 8080" > /dev/null; then python3 -m http.server 8080 --bind 127.0.0.1 -d /var/www > /dev/null 2>&1 & sleep 1; fi' >> /etc/bash.bashrc
    echo 'if ! pgrep -f "http.server 8080" > /dev/null; then python3 -m http.server 8080 --bind 127.0.0.1 -d /var/www > /dev/null 2>&1 & sleep 1; fi' >> /home/user/.bashrc

    chmod -R 777 /home/user
    chmod -R 755 /var/www
