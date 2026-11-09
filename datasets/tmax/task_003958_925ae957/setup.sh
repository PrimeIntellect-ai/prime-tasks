#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/web_logs.txt
192.168.1.50 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
10.5.5.101 - - [10/Oct/2023:13:56:10 -0700] "POST /api/v1/deploy HTTP/1.1" 403 152
172.16.0.42 - - [10/Oct/2023:13:58:22 -0700] "POST /api/v1/deploy HTTP/1.1" 201 512
192.168.1.50 - - [10/Oct/2023:14:00:01 -0700] "GET /api/v1/status HTTP/1.1" 200 45
EOF

    cat << 'EOF' > /home/user/rogue_auth.py
def authenticate(password):
    SECRET_HASH = "e382bbcdcf6071485dbce46fb2621189" # MD5 for "devsecops2023"
    import hashlib
    if hashlib.md5(password.encode()).hexdigest() == SECRET_HASH:
        return True
    return False
EOF

    python3 -m py_compile /home/user/rogue_auth.py
    mv /home/user/__pycache__/rogue_auth.cpython-*.pyc /home/user/rogue_auth.pyc
    rm -rf /home/user/rogue_auth.py /home/user/__pycache__

    cat << 'EOF' > /home/user/passwords.txt
admin123
password
qwerty
devsecops2023
letmein123
changeme
EOF

    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /home/user/rogue_cert.pem -days 365 -nodes -subj "/C=US/ST=CA/L=SanFrancisco/O=RogueCorp/CN=EvilHacker"

    chmod -R 777 /home/user
