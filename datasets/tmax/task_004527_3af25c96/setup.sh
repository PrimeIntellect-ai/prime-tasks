#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import os
import gzip
import zipfile
import tarfile
import random
import shutil

os.makedirs('/home/user/setup_tmp/serverA', exist_ok=True)
os.makedirs('/home/user/setup_tmp/serverB', exist_ok=True)

def generate_logs(filename, num_lines):
    levels = ['INFO', 'WARN', 'ERROR', 'DEBUG']
    modules = ['AUTH', 'DB', 'HTTP', 'SYSTEM']
    with open(filename, 'w') as f:
        for i in range(num_lines):
            level = random.choice(levels)
            # Ensure at least some ERRORs
            if i % 15 == 0: level = 'ERROR'
            line = f"2022-01-01 10:00:{i%60:02d}|{level}|{random.choice(modules)}|Message number {i}\n"
            f.write(line)

# Generate and gzip
for srv in ['serverA', 'serverB']:
    for log_num in range(1, 4):
        base_name = f"app_{log_num}.log"
        full_path = f"/home/user/setup_tmp/{srv}/{base_name}"
        generate_logs(full_path, 800)

        with open(full_path, 'rb') as f_in:
            with gzip.open(full_path + '.gz', 'wb') as f_out:
                f_out.writelines(f_in)
        os.remove(full_path)

# Zip
for srv in ['serverA', 'serverB']:
    with zipfile.ZipFile(f"/home/user/setup_tmp/{srv}.zip", 'w') as zf:
        for log_num in range(1, 4):
            gz_name = f"app_{log_num}.log.gz"
            zf.write(f"/home/user/setup_tmp/{srv}/{gz_name}", arcname=gz_name)

# Tar
with tarfile.open("/home/user/legacy_logs.tar", "w") as tf:
    tf.add("/home/user/setup_tmp/serverA.zip", arcname="serverA.zip")
    tf.add("/home/user/setup_tmp/serverB.zip", arcname="serverB.zip")

# Cleanup tmp
shutil.rmtree('/home/user/setup_tmp')
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
