#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/dummy_files
    cd /home/user/dummy_files

    # Create safe text file
    echo "config=1" > safe_config.txt

    # Create safe ELF file (dummy)
    printf '\x7F\x45\x4C\x46\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' > safe_bin.elf
    dd if=/dev/urandom bs=1 count=100 >> safe_bin.elf 2>/dev/null

    # Create malicious text file
    echo "root:x:0:0:root:/root:/bin/bash" > bad_shadow.txt

    # Create malicious ELF file
    printf '\x7F\x45\x4C\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' > bad_bin.elf

    # Create tar using python to manipulate names since tar might refuse to create absolute/traversal paths easily
    python3 -c '
import tarfile
import io

with tarfile.open("/home/user/config_update.tar", "w") as tar:
    # Safe text
    ti1 = tarfile.TarInfo(name="safe_config.txt")
    with open("safe_config.txt", "rb") as f:
        data1 = f.read()
    ti1.size = len(data1)
    tar.addfile(ti1, io.BytesIO(data1))

    # Safe ELF
    ti2 = tarfile.TarInfo(name="safe_bins/safe_bin.elf")
    with open("safe_bin.elf", "rb") as f:
        data2 = f.read()
    ti2.size = len(data2)
    tar.addfile(ti2, io.BytesIO(data2))

    # Malicious text 1 (../)
    ti3 = tarfile.TarInfo(name="../../etc/shadow")
    with open("bad_shadow.txt", "rb") as f:
        data3 = f.read()
    ti3.size = len(data3)
    tar.addfile(ti3, io.BytesIO(data3))

    # Malicious ELF (absolute path)
    ti4 = tarfile.TarInfo(name="/usr/bin/system_update")
    with open("bad_bin.elf", "rb") as f:
        data4 = f.read()
    ti4.size = len(data4)
    tar.addfile(ti4, io.BytesIO(data4))
'
    rm -rf /home/user/dummy_files

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/config_update.tar
    chmod -R 777 /home/user
