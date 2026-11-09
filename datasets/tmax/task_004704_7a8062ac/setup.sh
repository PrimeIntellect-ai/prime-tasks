#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak netcat-openbsd curl wget
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/webroot

    # Generate audio file
    espeak -w /app/incident_report.wav "The secret token is delta tango seven."

    # Create webroot files
    echo -n 'console.log("Normal JS");' > /home/user/webroot/app.js
    echo -n '<html><body>Tampered</body></html>' > /home/user/webroot/index.html

    # Create known_hashes.txt
    cd /home/user
    echo -n '<html><body>Original</body></html>' | sha256sum | awk '{print $1"  webroot/index.html"}' > known_hashes.txt
    sha256sum webroot/app.js >> known_hashes.txt

    # Create access.log
    cat << 'EOF' > /home/user/access.log
192.168.1.100 - - [10/Oct/2023:13:50:00 +0000] "GET / HTTP/1.1" 200
192.168.1.105 - - [10/Oct/2023:13:55:36 +0000] "GET /?cmd=base64_decode(XYZ) HTTP/1.1" 200
192.168.1.101 - - [10/Oct/2023:13:56:00 +0000] "GET /about.html HTTP/1.1" 200
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod 777 /app/incident_report.wav
