#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang gcc binutils coreutils
pip3 install pytest

mkdir -p /home/user

# Create a simple C file and compile it
cat << 'EOF' > /home/user/dummy.c
int main() { return 0; }
EOF
gcc /home/user/dummy.c -o /home/user/target_bin
rm /home/user/dummy.c

# Create the policy payload
PAYLOAD='{"env":"production","version":"1.2.3","signed":true}'
echo -n "$PAYLOAD" > /tmp/payload.json

# Base64 encode the payload (no newlines)
base64 -w 0 /tmp/payload.json > /tmp/payload.b64

# Inject it into the ELF as the .sec_policy section
objcopy --add-section .sec_policy=/tmp/payload.b64 /home/user/target_bin

# Clean up temp files
rm /tmp/payload.json /tmp/payload.b64

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
