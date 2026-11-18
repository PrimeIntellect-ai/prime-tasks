#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch tar coreutils diffutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup.py
import os
import subprocess

os.chdir('/home/user')

base_text = b"A" * 150 + b"B" * 100 + b"C" * 50 + b"\nBase data line 1.\nLine 2.\n"
updated_text = b"A" * 150 + b"B" * 100 + b"D" * 50 + b"\nBase data line 1 modified.\nLine 2.\nLine 3 added.\n"

with open("base_temp.txt", "wb") as f:
    f.write(base_text)
with open("updated_temp.txt", "wb") as f:
    f.write(updated_text)

rle_data = bytearray()
i = 0
while i < len(base_text):
    count = 1
    while i + count < len(base_text) and base_text[i] == base_text[i+count] and count < 255:
        count += 1
    rle_data.append(count)
    rle_data.append(base_text[i])
    i += count

with open("base.rle", "wb") as f:
    f.write(rle_data)

subprocess.run("diff -u base_temp.txt updated_temp.txt > update.patch", shell=True)

subprocess.run("tar -cvf split.tar base.rle update.patch", shell=True)
subprocess.run("split -b 500 split.tar split.tar.", shell=True)

subprocess.run("tar -czvf backup.tar.gz split.tar.*", shell=True)

subprocess.run("rm base_temp.txt updated_temp.txt base.rle update.patch split.tar split.tar.*", shell=True)
EOF

    python3 setup.py
    rm setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
