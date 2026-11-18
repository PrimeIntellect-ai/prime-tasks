#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
10.0.5.55 - - [10/Oct/2023:14:01:12 -0700] "GET /search.cgi?q=YXBwbGU%3D HTTP/1.1" 200 102
192.168.1.20 - - [10/Oct/2023:14:05:01 -0700] "GET /search.cgi?q=b3Jhbmdl HTTP/1.1" 200 95
172.16.4.101 - - [10/Oct/2023:14:15:22 -0700] "GET /search.cgi?q=OyBscyAtbGEgLw%3D%3D HTTP/1.1" 200 1520
172.16.4.101 - - [10/Oct/2023:14:18:10 -0700] "GET /search.cgi?q=OyBjYXQgL2V0Yy9wYXNzd2Q%3D HTTP/1.1" 200 3405
172.16.4.101 - - [10/Oct/2023:14:22:45 -0700] "GET /search.cgi?q=OyBuYyAtZSAvYmluL3NoIDEwLjEwLjEwLjEwIDQ0NDQ%3D HTTP/1.1" 200 45
10.0.5.55 - - [10/Oct/2023:14:25:00 -0700] "GET /search.cgi?q=YmFuYW5h HTTP/1.1" 200 110
EOF

    cat << 'EOF' > /home/user/search.cgi
#!/bin/bash
echo "Content-Type: text/plain"
echo ""
QUERY_STRING=${QUERY_STRING:-""}
Q_PARAM=$(echo "$QUERY_STRING" | grep -oP 'q=\K[^&]+')
# Vulnerable part
eval "grep -i $Q_PARAM /var/www/data.txt"
EOF
    chmod +x /home/user/search.cgi

    mkdir -p /var/www
    touch /var/www/data.txt

    chmod -R 777 /home/user
