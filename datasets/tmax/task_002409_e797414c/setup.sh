#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webapp/logs
    mkdir -p /home/user/webapp/cgi-bin
    mkdir -p /home/user/webapp/uploads
    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/webapp/cgi-bin/upload.sh
#!/bin/bash
# Insecure upload script
echo "Content-type: text/plain"
echo ""
# writes to relative paths without validation
EOF

    cat << 'EOF' > /home/user/webapp/logs/access.log
192.168.1.50 - - [10/Oct/2023:13:55:36 -0700] "GET / HTTP/1.1" 200 1024
192.168.1.50 - - [10/Oct/2023:13:55:40 -0700] "POST /cgi-bin/upload.sh?filename=test.txt HTTP/1.1" 200 45
10.0.45.22 - - [10/Oct/2023:14:02:11 -0700] "POST /cgi-bin/upload.sh?filename=../../../../etc/passwd HTTP/1.1" 403 211
172.16.8.99 - - [10/Oct/2023:14:15:02 -0700] "POST /cgi-bin/upload.sh?filename=../../../home/user/.ssh/authorized_keys HTTP/1.1" 200 85
172.16.8.99 - - [10/Oct/2023:14:15:05 -0700] "GET /cgi-bin/upload.sh HTTP/1.1" 200 112
EOF

    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... admin@corp.local
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAxx... pwned@hacker.net
EOF

    chmod -R 777 /home/user

    # Restore specific permissions required by the tests
    chmod 600 /home/user/.ssh/authorized_keys
    chmod 777 /home/user/webapp/cgi-bin/upload.sh
