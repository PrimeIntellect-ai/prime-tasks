#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest PyJWT

    mkdir -p /home/user/investigation
    cd /home/user/investigation

    # 1. Create the secret payload
    cat << 'EOF' > encode.py
import base64
secret = b"incident_response_secret_99"
xored = bytes([b ^ 0x5A for b in secret])
encoded = base64.b64encode(xored)
with open("payload.bin", "wb") as f:
    f.write(encoded)
EOF
    python3 encode.py

    # 2. Create a dummy ELF and inject the payload
    cat << 'EOF' > dummy.c
int main() { return 0; }
EOF
    gcc dummy.c -o suspicious.elf
    objcopy --add-section .hidden_payload=payload.bin suspicious.elf

    # 3. Generate access logs with some valid and invalid JWTs
    cat << 'EOF' > gen_logs.py
import jwt

secret = "incident_response_secret_99"
bad_secret = "wrong_secret_123"

# Valid tokens
t1 = jwt.encode({"user": "admin"}, secret, algorithm="HS256")
t2 = jwt.encode({"user": "system"}, secret, algorithm="HS256")
# Invalid token
t3 = jwt.encode({"user": "hacker"}, bad_secret, algorithm="HS256")

logs = [
    f'192.168.1.10 - - [25/Oct/2023:14:30:00 +0000] "GET /index.html HTTP/1.1" 200 1024 "-" "Mozilla/5.0"',
    f'10.4.5.22 - - [25/Oct/2023:14:32:01 +0000] "GET /api/v1/admin/dump HTTP/1.1" 200 4096 "-" "Bearer {t1}"',
    f'172.16.0.5 - - [25/Oct/2023:14:35:10 +0000] "POST /api/v1/user/update HTTP/1.1" 401 256 "-" "Bearer {t3}"',
    f'8.8.8.8 - - [25/Oct/2023:14:40:22 +0000] "GET /api/v1/system/keys HTTP/1.1" 200 512 "-" "Bearer {t2}"'
]

with open("access.log", "w") as f:
    for log in logs:
        f.write(log + "\n")
EOF
    python3 gen_logs.py

    # Cleanup
    rm dummy.c encode.py gen_logs.py payload.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
