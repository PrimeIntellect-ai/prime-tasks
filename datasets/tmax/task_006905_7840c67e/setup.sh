#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads

    python3 -c "
import os

os.makedirs('/home/user/uploads', exist_ok=True)

with open('/home/user/uploads/file1.bin', 'wb') as f:
    f.write(b'\x7fELF\x01\x01\x01\x00safe_content_here')

with open('/home/user/uploads/file2.bin', 'wb') as f:
    f.write(b'\x7fELF\x02\x01\x01\x00...malicious_payload_x86...')

with open('/home/user/uploads/file3.bin', 'wb') as f:
    f.write(b'Just a normal text file')

with open('/home/user/uploads/file4.bin', 'wb') as f:
    f.write(b'\x7fELF\x01\x01safe')

with open('/home/user/uploads/file5.bin', 'wb') as f:
    f.write(b'MZ\x00\x00...malicious_payload_x86...')
"

    cat << 'EOF' > /home/user/metadata.json
[
  {"filename": "file1.bin", "original_path": "uploads/file1.bin", "csp_directive": "strict-dynamic"},
  {"filename": "file2.bin", "original_path": "uploads/file2.bin", "csp_directive": "strict-dynamic"},
  {"filename": "file3.bin", "original_path": "uploads/file3.bin", "csp_directive": "unsafe-inline"},
  {"filename": "file4.bin", "original_path": "../../../etc/passwd", "csp_directive": "strict-dynamic"},
  {"filename": "file5.bin", "original_path": "uploads/file5.bin", "csp_directive": "strict-dynamic"}
]
EOF

    chmod -R 777 /home/user
