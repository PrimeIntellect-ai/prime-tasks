#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    echo '127.0.0.1 - - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 612 "-" "Mozilla/5.0"' > /app/corpora/clean/1.log
    echo '192.168.1.1 - - [10/Oct/2023:13:55:37 +0000] "POST /api/login HTTP/1.1" 201 123 "-" "curl/7.68.0"' > /app/corpora/clean/2.log

    echo '127.0.0.1 - - [10/Oct/2023:13:56:00 +0000] "GET /../../../etc/passwd HTTP/1.1" 404 153 "-" "Mozilla/5.0"' > /app/corpora/evil/1.log
    echo '127.0.0.1 - - [10/Oct/2023:13:56:01 +0000] "GET /?id=1%27%20OR%201=1 HTTP/1.1" 200 612 "-" "Mozilla/5.0"' > /app/corpora/evil/2.log
    echo -e '127.0.0.1 - - [10/Oct/2023:13:56:02 +0000] "GET /bad\xff\xfe HTTP/1.1" 400 120 "-" "curl"' > /app/corpora/evil/3.log
    echo '127.0.0.1 - - [10/Oct/2023:13:56:03 +0000] "GET /?q=<script>alert(1)</script> HTTP/1.1" 200 612 "-" "Mozilla"' > /app/corpora/evil/4.log

    echo "server { listen 8080  location / { root /var/www/html; } }" > /etc/nginx/sites-enabled/default

    cat << 'EOF' > /app/log_ingest.sh
#!/bin/bash
tail -F /var/log/nginx/access.log | while read line; do
    # Agent needs to pipe $line through the sanitizer script here
    redis-cli -p 6380 rpush raw_logs "$line"
done
EOF
    chmod +x /app/log_ingest.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
