#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev openssl
pip3 install pytest

useradd -m -s /bin/bash user || true

cd /home/user

# Generate CA and Server Certs
openssl req -x509 -sha256 -days 365 -nodes -newkey rsa:2048 -subj "/CN=TargetRootCA" -keyout ca.key -out ca.crt
openssl req -new -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=TargetServer"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365 -sha256

# Create the encoded payload
python3 -c '
import base64
text = b"RED_TEAM_STRIKES_AGAIN_WITH_C++!"
xor_text = bytes([b ^ 0x42 for b in text])
b64_text = base64.b64encode(xor_text)
with open("payload.enc", "wb") as f:
    f.write(b64_text)
'

chmod -R 777 /home/user
