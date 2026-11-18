#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
os.makedirs('/home/user/uploads', exist_ok=True)
with open('/home/user/uploads/clean.txt', 'w') as f:
    f.write('User login successful. IP: 192.168.1.50')
with open('/home/user/uploads/traversal.txt', 'w') as f:
    f.write('profile_image=../../../etc/passwd')
with open('/home/user/uploads/xss.txt', 'w') as f:
    f.write(\"comment=Nice post! <script>fetch('http://evil.com')</script>\")
with open('/home/user/uploads/hidden.enc', 'wb') as f:
    f.write(bytes([b ^ 0x37 for b in b'avatar=x onerror=alert(1)']))
"

    chmod -R 777 /home/user
