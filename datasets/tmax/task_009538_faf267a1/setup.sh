#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile
import tarfile
import shutil
import hashlib

base_dir = "/home/user/setup_temp"
os.makedirs(base_dir, exist_ok=True)

# Trial 1: Alpha (Valid)
os.makedirs(f"{base_dir}/Alpha_Dir")
with open(f"{base_dir}/Alpha_Dir/metadata.xml", "w") as f:
    f.write("<trial>\n  <id>Alpha_01</id>\n  <valid>true</valid>\n  <binary_offset>10</binary_offset>\n  <binary_length>16</binary_length>\n</trial>")
with open(f"{base_dir}/Alpha_Dir/sensors.csv", "w") as f:
    f.write("timestamp,value\n1,10.5\n2,20.5\n3,30.0\n")
with open(f"{base_dir}/Alpha_Dir/data.bin", "wb") as f:
    f.write(b"A" * 10 + b"B" * 16 + b"C" * 10)

# Trial 2: Beta (Invalid)
os.makedirs(f"{base_dir}/Beta_Dir")
with open(f"{base_dir}/Beta_Dir/metadata.xml", "w") as f:
    f.write("<trial>\n  <id>Beta_02</id>\n  <valid>false</valid>\n  <binary_offset>0</binary_offset>\n  <binary_length>5</binary_length>\n</trial>")
with open(f"{base_dir}/Beta_Dir/sensors.csv", "w") as f:
    f.write("timestamp,value\n1,99.9\n")
with open(f"{base_dir}/Beta_Dir/data.bin", "wb") as f:
    f.write(b"X" * 20)

# Trial 3: Gamma (Valid)
os.makedirs(f"{base_dir}/Gamma_Dir")
with open(f"{base_dir}/Gamma_Dir/metadata.xml", "w") as f:
    f.write("<trial>\n  <id>Gamma_03</id>\n  <valid>true</valid>\n  <binary_offset>5</binary_offset>\n  <binary_length>8</binary_length>\n</trial>")
with open(f"{base_dir}/Gamma_Dir/sensors.csv", "w") as f:
    f.write("timestamp,value\n1,100.1\n2,100.2\n")
with open(f"{base_dir}/Gamma_Dir/data.bin", "wb") as f:
    f.write(b"Y" * 5 + b"Z" * 8 + b"W" * 5)

# Archive Creation (Nesting)
shutil.make_archive(f"{base_dir}/inner1", 'gztar', root_dir=base_dir, base_dir="Alpha_Dir")
shutil.make_archive(f"{base_dir}/inner2", 'zip', root_dir=base_dir, base_dir="Beta_Dir")
shutil.make_archive(f"{base_dir}/inner3", 'gztar', root_dir=base_dir, base_dir="Gamma_Dir")

os.makedirs(f"{base_dir}/wrapper")
shutil.move(f"{base_dir}/inner1.tar.gz", f"{base_dir}/wrapper/inner1.tar.gz")
shutil.move(f"{base_dir}/inner2.zip", f"{base_dir}/wrapper/inner2.zip")
shutil.move(f"{base_dir}/inner3.tar.gz", f"{base_dir}/wrapper/inner3.tar.gz")

shutil.make_archive(f"/home/user/research_data", 'zip', root_dir=base_dir, base_dir="wrapper")
shutil.rmtree(base_dir)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
