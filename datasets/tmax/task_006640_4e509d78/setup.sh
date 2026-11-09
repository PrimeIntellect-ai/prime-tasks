#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident/logs
    mkdir -p /home/user/incident/cgi-bin
    mkdir -p /home/user/incident/backups
    mkdir -p /home/user/incident/current

    cat << 'EOF' > /home/user/incident/logs/access.log
10.0.0.15 - - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 1024
192.168.1.55 - - [10/Oct/2023:14:02:11 +0000] "GET /cgi-bin/download.sh?file=report.pdf HTTP/1.1" 200 4501
192.168.1.55 - - [10/Oct/2023:14:05:22 +0000] "GET /cgi-bin/download.sh?file=../../../../etc/shadow HTTP/1.1" 200 892
10.0.0.22 - - [10/Oct/2023:14:10:05 +0000] "GET /cgi-bin/download.sh?file=../etc/passwd HTTP/1.1" 403 212
EOF

    cat << 'EOF' > /home/user/incident/logs/auth.log
Oct 10 13:01:12 server sshd[1201]: Accepted publickey for admin from 10.0.0.15 port 54321 ssh2
Oct 10 14:15:33 server sshd[1455]: Failed password for root from 192.168.1.55 port 39412 ssh2
Oct 10 14:22:01 server sshd[1489]: Accepted password for dev_carl from 192.168.1.55 port 39488 ssh2
Oct 10 14:25:10 server sshd[1502]: Accepted publickey for backup_svc from 10.0.0.50 port 44321 ssh2
EOF

    cat << 'EOF' > /home/user/incident/cgi-bin/download.sh
#!/bin/bash
# CGI Download Handler
echo "Content-Type: application/octet-stream"
echo ""

FILE_PARAM=$1
# Vulnerability: No input validation
cat "/var/www/uploads/$FILE_PARAM"
EOF
    chmod +x /home/user/incident/cgi-bin/download.sh

    echo "server_port=8080" > /home/user/incident/backups/server.conf
    echo "timeout=30" > /home/user/incident/backups/app.properties
    echo "root_email=admin@local" > /home/user/incident/backups/mail.rc

    echo "server_port=8080" > /home/user/incident/current/server.conf
    echo "timeout=300" > /home/user/incident/current/app.properties
    echo "root_email=hacker@evil.com" > /home/user/incident/current/mail.rc

    chmod -R 777 /home/user
