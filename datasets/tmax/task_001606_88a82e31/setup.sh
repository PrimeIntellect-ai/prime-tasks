#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/evidence
    cd /home/user/evidence

    # Create the key
    echo -n "h4x0rK3y" > key.txt

    # Create the original raw payload
    cat << 'EOF' > payload.txt
GET /login?user=admin&password=SuperSecret123&redirect=http://evil.com/log HTTP/1.1
Host: example.com
User-Agent: Mozilla/5.0

GET /login?user=jsmith&password=MyP@ssw0rd!&redirect=http://evil.com/log HTTP/1.1
Host: example.com
User-Agent: curl/7.68.0
EOF

    # Calculate and store checksum
    sha256sum payload.txt | awk '{print $1}' > checksum.sha256

    # Encrypt payload with repeating XOR
    python3 -c "
import sys
key = b'h4x0rK3y'
with open('payload.txt', 'rb') as f:
    data = f.read()
enc = bytes([data[i] ^ key[i % len(key)] for i in range(len(data))])
with open('payload.enc', 'wb') as f:
    f.write(enc)
"

    # Create a dummy ELF binary
    cat << 'EOF' > dummy.c
int main() { return 0; }
EOF
    gcc dummy.c -o malware_base.bin

    # Inject the encrypted payload into the ELF as .exfil section
    objcopy --add-section .exfil=payload.enc --set-section-flags .exfil=alloc,readonly malware_base.bin malware.bin

    # Cleanup intermediate files
    rm dummy.c malware_base.bin payload.txt payload.enc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
