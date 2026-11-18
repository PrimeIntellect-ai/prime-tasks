#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo tar bzip2 gzip gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import tarfile
import bz2

base_dir = "/home/user/backups"
os.makedirs(base_dir, exist_ok=True)

# App Alpha Data
alpha_servers = """
  192.168.1.10 ; database node
192.168.1.11   
; 192.168.1.12 offline
  10.0.0.5 ; web
"""

alpha_log = """Commit: abc123def
Author: admin
Date: 2023-10-01
---
Commit: 456bca
Author: user1
Date: 2023-10-02
---
"""

# App Beta Data
beta_servers = """
172.16.0.4; cache
  172.16.0.5  
"""

beta_log = """Commit: 789xyz
Author: admin
Date: 2023-10-05
---
Commit: 101112abc
Author: admin
Date: 2023-10-06
---
"""

def write_bin(filename, records):
    with open(filename, 'wb') as f:
        f.write(b'\x43\x46\x47\x01') # CFG\x01
        f.write(struct.pack('<I', len(records)))
        for k, v in records:
            f.write(struct.pack('B', len(k)))
            f.write(k.encode('utf-8'))
            f.write(struct.pack('<I', v))

os.makedirs("/tmp/app_alpha", exist_ok=True)
with open("/tmp/app_alpha/servers.conf", "w") as f: f.write(alpha_servers)
with open("/tmp/app_alpha/changes.log", "w") as f: f.write(alpha_log)
write_bin("/tmp/app_alpha/state.bin", [("db_port", 5432), ("max_conn", 100)])

os.makedirs("/tmp/app_beta", exist_ok=True)
with open("/tmp/app_beta/servers.conf", "w") as f: f.write(beta_servers)
with open("/tmp/app_beta/changes.log", "w") as f: f.write(beta_log)
write_bin("/tmp/app_beta/state.bin", [("cache_size", 2048)])

# Create inner bz2 tars
def create_tar_bz2(source_dir, output_filename):
    with tarfile.open(output_filename, "w:bz2") as tar:
        tar.add(source_dir, arcname=os.path.basename(source_dir))

create_tar_bz2("/tmp/app_alpha", "/tmp/app_alpha.tar.bz2")
create_tar_bz2("/tmp/app_beta", "/tmp/app_beta.tar.bz2")

# Create outer gz tar
with tarfile.open(f"{base_dir}/infra_state.tar.gz", "w:gz") as tar:
    tar.add("/tmp/app_alpha.tar.bz2", arcname="app_alpha.tar.bz2")
    tar.add("/tmp/app_beta.tar.bz2", arcname="app_beta.tar.bz2")
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/app_alpha /tmp/app_beta /tmp/app_alpha.tar.bz2 /tmp/app_beta.tar.bz2 /tmp/setup.py

    chmod -R 777 /home/user
