#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip file binutils
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/build_dump

# 1. Create valid 64-bit ELF binaries
cp /bin/ls /home/user/build_dump/binary1_ls
cp /bin/cat /home/user/build_dump/binary2_cat
cp /bin/echo /home/user/build_dump/binary3_echo.elf

# 2. Create invalid / corrupted ELFs
# Corrupted ELF 1: Only magic bytes
/bin/bash -c "printf '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' > /home/user/build_dump/corrupt1.elf"
head -c 100 /dev/urandom >> /home/user/build_dump/corrupt1.elf

# Corrupted ELF 2: 32-bit ELF (should be ignored since we want 64-bit)
# We mock a 32-bit ELF header
/bin/bash -c "printf '\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' > /home/user/build_dump/corrupt2_32bit.elf"
head -c 100 /dev/urandom >> /home/user/build_dump/corrupt2_32bit.elf

# 3. Create log files
# Log 1: 120 KB -> should create 3 chunks (50k, 50k, 20k)
head -c 122880 /dev/urandom | base64 | head -c 122880 > /home/user/build_dump/system_run.log

# Log 2: 40 KB -> should create 1 chunk (40k)
head -c 40960 /dev/urandom | base64 | head -c 40960 > /home/user/build_dump/error_dump.log

# Log 3: 160 KB -> should create 4 chunks (50k, 50k, 50k, 10k)
head -c 163840 /dev/urandom | base64 | head -c 163840 > /home/user/build_dump/access.log

chown -R user:user /home/user/build_dump
chmod -R 777 /home/user
