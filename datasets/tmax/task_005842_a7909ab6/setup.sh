#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user

    # 1. Create firewall.txt
    cat << 'EOF' > /home/user/firewall.txt
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -s 192.168.1.0/24 -p tcp -m tcp --dport 8080 -j ACCEPT
-A INPUT -s 203.0.113.50/32 -p tcp -m tcp --dport 9443 -j ACCEPT
-A INPUT -s 10.0.0.5/32 -p tcp -m tcp --dport 3306 -j ACCEPT
COMMIT
EOF

    # 2. Create server.pem and server.key
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/server.key -out /home/user/server.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Company/CN=internal.service.local"

    # 3. Create crypto_auth.py
    cat << 'EOF' > /home/user/crypto_auth.py
def verify_token(token, username):
    """
    Verifies the authentication token for a given username.
    The token is expected to be a hex string.
    """
    try:
        raw_token = bytes.fromhex(token)
        key = b"sUp3r_s3cr3t_k3y"

        # Simple XOR decryption
        decrypted = bytearray()
        for i, byte in enumerate(raw_token):
            decrypted.append(byte ^ key[i % len(key)])

        return decrypted.decode('utf-8') == username
    except Exception:
        return False
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
