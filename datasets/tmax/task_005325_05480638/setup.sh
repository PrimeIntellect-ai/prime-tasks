#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app.py
def beacon():
    c2_ip = "203.0.113.88"
    token = "Auth-99b-XYZ"
    return c2_ip, token
EOF

    python3 -c "import py_compile; py_compile.compile('/home/user/app.py', cfile='/home/user/app.pyc')"
    rm /home/user/app.py

    cat << 'EOF' > /home/user/traffic.log
{"method": "POST", "ip": "203.0.113.88", "headers": {"X-Auth-Token": "Auth-99b-XYZ"}, "body": "User data: SSN 123-45-6789 found."}
{"method": "POST", "ip": "203.0.113.88", "headers": {"X-Auth-Token": "WrongToken"}, "body": "User data: SSN 987-65-4321 found."}
{"method": "GET", "ip": "203.0.113.88", "headers": {"X-Auth-Token": "Auth-99b-XYZ"}, "body": "Ping"}
{"method": "POST", "ip": "198.51.100.1", "headers": {"X-Auth-Token": "Auth-99b-XYZ"}, "body": "Data: 111-22-3333"}
{"method": "POST", "ip": "203.0.113.88", "headers": {"X-Auth-Token": "Auth-99b-XYZ"}, "body": "More data, SSN 555-66-7777 and 888-99-0000."}
EOF

    chmod -R 777 /home/user
