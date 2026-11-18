#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create auth_algo.py
    cat << 'EOF' > auth_algo.py
def generate_response(password: str, challenge: str) -> str:
    """Custom FNV-1a inspired weak hash for IoT authentication."""
    state = 0x811C9DC5
    for char in password + challenge:
        state = (state ^ ord(char)) * 0x01000193
        state &= 0xFFFFFFFF
    return f"{state:08x}"
EOF

    # Create wordlist.txt
    cat << 'EOF' > wordlist.txt
password123
admin
admin123
root
letmein
networkeng
cisco123
iotdevice
supersecret
admintiger
sunshine
EOF

    # Create traffic_capture.log
    cat << 'EOF' > traffic_capture.log
[10:22:01] 192.168.1.55 -> 192.168.1.100: AUTH_REQ user=guest
[10:22:01] 192.168.1.100 -> 192.168.1.55: AUTH_CHAL chal=chal_11223
[10:22:02] 192.168.1.55 -> 192.168.1.100: AUTH_RESP resp=d4b29a10
[10:22:02] 192.168.1.100 -> 192.168.1.55: AUTH_FAIL
[10:24:15] 192.168.1.88 -> 192.168.1.100: AUTH_REQ user=admin
[10:24:15] 192.168.1.100 -> 192.168.1.88: AUTH_CHAL chal=chal_9f8a2
[10:24:16] 192.168.1.88 -> 192.168.1.100: AUTH_RESP resp=13e4b7c6
[10:24:16] 192.168.1.100 -> 192.168.1.88: AUTH_SUCCESS
EOF

    # Next challenge
    echo -n "chal_5x99b" > next_challenge.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
