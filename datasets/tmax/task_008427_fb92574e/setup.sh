#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import binascii

def xor_crypt(data, key):
    return bytes([data[i] ^ key[i % len(key)] for i in range(len(data))])

key = b'S3cr3t'

guest_pt = b'USER:guest;ROLE:guest;TS:1700000000'
admin_pt = b'USER:admin;ROLE:admin;TS:1700000055'

guest_enc = binascii.hexlify(xor_crypt(guest_pt, key)).decode('utf-8')
admin_enc = binascii.hexlify(xor_crypt(admin_pt, key)).decode('utf-8')

log_content = f'''[1700000000] 192.168.1.10 GET /login?redirect=/dashboard&user=guest {guest_enc}
[1700000010] 10.0.0.5 GET /login?redirect=/settings&user=user1 5e0640523a1a46505f4c107246415f530e160451450201103f56
[1700000020] 203.0.113.42 GET /login?redirect=http://evil.com/steal&user=guest {guest_enc}
[1700000055] 127.0.0.1 GET /login?redirect=/admin&user=admin {admin_enc}
[1700000060] 203.0.113.42 GET /login?redirect=/home&payload=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaac 5e0640523a1a46505f4c107246415f530e160451450201103f56
'''

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/server.log', 'w') as f:
    f.write(log_content)
"

    chmod -R 777 /home/user
