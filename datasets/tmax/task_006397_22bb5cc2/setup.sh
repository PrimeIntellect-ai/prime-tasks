#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest PyJWT

    mkdir -p /home/user/certs
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/auth.log
[2023-10-24 10:00:01] IP: 192.168.1.15 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMSIsIm1hbGljaW91cyI6ZmFsc2V9.dummy_sig
[2023-10-24 10:05:22] IP: 10.0.5.55 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJoYWNrZXIiLCJtYWxpY2lvdXMiOnRydWV9.dummy_sig
[2023-10-24 10:10:00] IP: 172.16.0.4 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJndWVzdCIsIm1hbGljaW91cyI6ZmFsc2V9.dummy_sig
[2023-10-24 10:15:10] IP: 10.0.5.55 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJyb290IiwibWFsaWNpb3VzIjp0cnVlfQ.dummy_sig
[2023-10-24 10:20:00] IP: 192.168.100.2 Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZG1pbiIsIm1hbGljaW91cyI6dHJ1ZX0.dummy_sig
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
