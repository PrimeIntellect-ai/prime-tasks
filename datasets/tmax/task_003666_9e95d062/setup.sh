#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_key.py
def generate_key(seed):
    # Custom fast PRNG for key generation
    a = 1103515245
    c = 12345
    m = 2147483647
    return (a * seed + c) % m

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        print(generate_key(int(sys.argv[1])))
EOF

    echo -n "153028214" > /home/user/old_key.txt

    mkdir -p /home/user/certs
    cd /home/user/certs

    # 1. Root CA
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout root.key -out root.crt -subj "/CN=RootCA"

    # 2. Intermediate CA
    openssl req -newkey rsa:2048 -nodes -keyout int.key -out int.csr -subj "/CN=IntCA"
    echo "basicConstraints=CA:TRUE" > extfile.cnf
    openssl x509 -req -in int.csr -CA root.crt -CAkey root.key -CAcreateserial -out int.crt -days 365 -extfile extfile.cnf

    # 3. Leaf Certificate
    openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=internal-service.local"
    openssl x509 -req -in leaf.csr -CA int.crt -CAkey int.key -CAcreateserial -out leaf.crt -days 365

    # Bundle them into bundle.pem (Leaf -> Intermediate -> Root)
    cat leaf.crt int.crt root.crt > /home/user/bundle.pem

    chmod -R 777 /home/user
