#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming

    cat << 'EOF' > /tmp/setup.py
import os
import gzip
import random

os.makedirs("/home/user/incoming", exist_ok=True)

# Generate consistent mock data
random.seed(42)

def make_elf(seed_val):
    random.seed(seed_val)
    # \x7fELF + 1020 random bytes
    return b'\x7fELF' + bytes([random.randint(0, 255) for _ in range(1020)])

def make_garbage(seed_val):
    random.seed(seed_val)
    return bytes([random.randint(0, 255) for _ in range(1024)])

# Definitions of the incoming files
files_spec = [
    ("art_01.bin.gz", "elf_1"),      # Unique ELF 1
    ("art_02.bin.gz", "garbage_1"),  # Garbage
    ("art_03.bin.gz", "elf_2"),      # Unique ELF 2
    ("art_04.bin.gz", "elf_1"),      # Duplicate of ELF 1
    ("art_05.bin.gz", "elf_3"),      # Unique ELF 3
    ("art_06.bin.gz", "garbage_2"),  # Garbage
    ("art_07.bin.gz", "elf_2"),      # Duplicate of ELF 2
    ("art_08.bin.gz", "elf_2"),      # Duplicate of ELF 2
]

# Generate the files
for fname, ftype in files_spec:
    path = os.path.join("/home/user/incoming", fname)
    if ftype == "elf_1":
        content = make_elf(1)
    elif ftype == "elf_2":
        content = make_elf(2)
    elif ftype == "elf_3":
        content = make_elf(3)
    elif ftype == "garbage_1":
        content = make_garbage(10)
    elif ftype == "garbage_2":
        content = make_garbage(20)

    with gzip.open(path, 'wb') as f:
        f.write(content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
