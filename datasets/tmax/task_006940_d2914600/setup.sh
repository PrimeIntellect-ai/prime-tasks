#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/forensics/system_root/usr/bin
    mkdir -p /home/user/forensics/system_root/etc
    mkdir -p /home/user/forensics/system_root/var/log
    mkdir -p /home/user/forensics/logs

    # Create decoy files
    touch /home/user/forensics/system_root/usr/bin/ls
    touch /home/user/forensics/system_root/usr/bin/cat

    # Create the HTTP logs
    cat << 'EOF' > /home/user/forensics/logs/http_req.log
GET /index.html HTTP/1.1
Host: www.example.com
User-Agent: Mozilla/5.0
Cookie: session_id=8472948293

POST /login HTTP/1.1
Host: www.example.com
User-Agent: Mozilla/5.0
Cookie: session_id=8472948293

GET /images/logo.png HTTP/1.1
Host: www.example.com
User-Agent: curl/7.68.0
Cookie: MalCookie=YWRtaW5fcGFzc3dvcmQ9SDBudDNyU2VjcmV0IQ==

GET /about.html HTTP/1.1
Host: www.example.com
User-Agent: Mozilla/5.0
Cookie: session_id=9938472911
EOF

    # Create the SUID backdoor binary
    echo 'int main(){ setuid(0); system("/bin/bash"); return 0; }' > /home/user/forensics/system_root/var/log/.hidden_shell

    # Apply general permissions first
    chmod -R 777 /home/user

    # Apply specific permissions after
    chmod 755 /home/user/forensics/system_root/usr/bin/ls
    chmod 755 /home/user/forensics/system_root/usr/bin/cat
    chmod 4755 /home/user/forensics/system_root/var/log/.hidden_shell
