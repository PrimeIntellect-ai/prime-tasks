#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip unzip tar gzip
pip3 install pytest

# Create setup script to generate initial state
cat << 'EOF' > /tmp/setup.py
import os
import struct
import zipfile
import tarfile

# Create workspace
base_dir = "/home/user"
os.makedirs(base_dir, exist_ok=True)

# Generate dummy ELF headers
def create_dummy_elf(path, machine_type):
    # e_ident: 16 bytes. Magic is \x7fELF
    e_ident = b'\x7fELF' + b'\x00' * 12
    # e_type: 2 bytes
    e_type = b'\x02\x00'
    # e_machine: 2 bytes
    e_machine = struct.pack('<H', machine_type)
    # the rest (just pad to 64 bytes)
    header = e_ident + e_type + e_machine + b'\x00' * 44
    with open(path, 'wb') as f:
        f.write(header)

os.makedirs("/tmp/setup_elfs/dir1", exist_ok=True)
os.makedirs("/tmp/setup_elfs/dir2", exist_ok=True)

# Create files
create_dummy_elf("/tmp/setup_elfs/dir1/sensor_read", 0x28) # ARM
create_dummy_elf("/tmp/setup_elfs/dir1/web_server", 0x3E) # x86_64
create_dummy_elf("/tmp/setup_elfs/dir2/data_logger", 0x28) # ARM

# Non-ELF files
with open("/tmp/setup_elfs/dir1/notes.txt", "w") as f:
    f.write("Just some notes.")
with open("/tmp/setup_elfs/dir2/model.gcode", "w") as f:
    f.write("G28\nG1 X10 Y10\n")

# Zip them up
with zipfile.ZipFile("/tmp/setup_elfs/part1.zip", "w") as z:
    z.write("/tmp/setup_elfs/dir1/sensor_read", "sensor_read")
    z.write("/tmp/setup_elfs/dir1/web_server", "web_server")
    z.write("/tmp/setup_elfs/dir1/notes.txt", "notes.txt")

with zipfile.ZipFile("/tmp/setup_elfs/part2.zip", "w") as z:
    z.write("/tmp/setup_elfs/dir2/data_logger", "data_logger")
    z.write("/tmp/setup_elfs/dir2/model.gcode", "model.gcode")

# Tar them up
with tarfile.open(f"{base_dir}/project_artifacts.tar.gz", "w:gz") as t:
    t.add("/tmp/setup_elfs/part1.zip", arcname="part1.zip")
    t.add("/tmp/setup_elfs/part2.zip", arcname="part2.zip")

# Cleanup /tmp
os.system("rm -rf /tmp/setup_elfs")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
