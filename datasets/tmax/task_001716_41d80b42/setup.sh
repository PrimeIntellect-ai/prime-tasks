#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import zipfile
import tarfile
import os
import io

os.makedirs('/home/user/datasets', exist_ok=True)

# Safe 1
with zipfile.ZipFile('/home/user/datasets/safe1.zip', 'w') as z:
    z.writestr('model.gcode', "G1 X10 E5.5\nG0 Z1\nG1 Y20 E4.5\n")
    elf_data = b'\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00' + b'\x00'*40
    z.writestr('bin/program', elf_data)

# Malicious 1
with zipfile.ZipFile('/home/user/datasets/malicious1.zip', 'w') as z:
    z.writestr('../evil.sh', "echo 'hacked'")

# Malicious 2
with tarfile.open('/home/user/datasets/malicious2.tar.gz', 'w:gz') as t:
    tinfo = tarfile.TarInfo(name='/etc/passwd')
    tinfo.size = 4
    t.addfile(tinfo, io.BytesIO(b"root"))

# Safe 2
with tarfile.open('/home/user/datasets/safe2.tar.gz', 'w:gz') as t:
    tinfo = tarfile.TarInfo(name='part.gcode')
    gcode = b"G1 E100.1\nG1 E200.2\n"
    tinfo.size = len(gcode)
    t.addfile(tinfo, io.BytesIO(gcode))

    elf_data = b'\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00' + b'\x00'*40
    tinfo2 = tarfile.TarInfo(name='arm_bin')
    tinfo2.size = len(elf_data)
    t.addfile(tinfo2, io.BytesIO(elf_data))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
