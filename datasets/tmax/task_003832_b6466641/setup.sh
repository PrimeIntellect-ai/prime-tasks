#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/backups /home/user/extracted_logs /home/user/processed_logs
echo "SECURE_STATE" > /home/user/system_state.json

# Create the nested archives with tar slip payload
cat << 'EOF' > /tmp/setup.py
import struct
import tarfile
import os
import io

# Helper to create .blog files
def create_blog(records):
    data = bytearray()
    data.extend(b'BLOG')
    for ts, ev, sev, payload in records:
        payload_bytes = payload.encode('ascii')
        data.extend(struct.pack('<IHBB', ts, ev, sev, len(payload_bytes)))
        data.extend(payload_bytes)
    return data

blog1 = create_blog([(1600000000, 10, 1, "System start"), (1600000005, 12, 2, "Warning temp")])
blog2 = create_blog([(1600000010, 15, 0, "All good")])
blog3 = create_blog([(1600000020, 99, 3, "Fatal error")])

os.makedirs("/tmp/archive_gen/inner1", exist_ok=True)
os.makedirs("/tmp/archive_gen/inner2", exist_ok=True)

with open("/tmp/archive_gen/inner1/alpha.blog", "wb") as f: f.write(blog1)
with open("/tmp/archive_gen/inner1/beta.blog", "wb") as f: f.write(blog2)
with open("/tmp/archive_gen/inner2/gamma.blog", "wb") as f: f.write(blog3)

# Create inner1.tar
with tarfile.open("/tmp/inner1.tar", "w") as tar:
    tar.add("/tmp/archive_gen/inner1/alpha.blog", arcname="alpha.blog")
    tar.add("/tmp/archive_gen/inner1/beta.blog", arcname="beta.blog")

# Create inner2.tar with a Tar Slip payload
with tarfile.open("/tmp/inner2.tar", "w") as tar:
    tar.add("/tmp/archive_gen/inner2/gamma.blog", arcname="gamma.blog")

    # Tar slip payload
    tarinfo = tarfile.TarInfo(name="../../../../../../../../home/user/system_state.json")
    tarinfo.size = 14
    tar.addfile(tarinfo, io.BytesIO(b"COMPROMISED!!!"))

# Create master
with tarfile.open("/home/user/backups/master_backup.tar.gz", "w:gz") as tar:
    tar.add("/tmp/inner1.tar", arcname="inner1.tar")
    tar.add("/tmp/inner2.tar", arcname="nested/inner2.tar")
EOF

python3 /tmp/setup.py
rm -rf /tmp/setup.py /tmp/archive_gen /tmp/inner1.tar /tmp/inner2.tar

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
