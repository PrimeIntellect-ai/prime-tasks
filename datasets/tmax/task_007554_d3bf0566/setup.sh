#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import gzip
import zipfile

# Create directories
os.makedirs('/home/user/user_uploads', exist_ok=True)

# 1. Config file
config_content = """[Scan]
target_directory = /home/user/user_uploads
report_path = /home/user/hidden_archives.log
"""
with open('/home/user/scan_config.ini', 'w') as f:
    f.write(config_content)

# 2. Real text file disguised as log
with open('/home/user/user_uploads/app_debug.log', 'w') as f:
    f.write("Just a normal text file with log data " * 100)

# 3. GZIP file disguised as .txt
with gzip.open('/home/user/user_uploads/notes.txt', 'wb') as f:
    f.write(b"This is some hidden compressed data " * 500)

# 4. ZIP file disguised as .dat
with zipfile.ZipFile('/home/user/user_uploads/system_cache.dat', 'w') as z:
    z.writestr('secret_stuff.txt', b"Hidden zip content " * 500)

# 5. Real binary (non-archive) disguised as .conf
with open('/home/user/user_uploads/settings.conf', 'wb') as f:
    f.write(b"\x00\x01\x02\x03\x04" * 100)

# 6. GZIP file disguised as .csv
with gzip.open('/home/user/user_uploads/financials.csv', 'wb') as f:
    f.write(b"1,2,3,4,5\n" * 1000)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
