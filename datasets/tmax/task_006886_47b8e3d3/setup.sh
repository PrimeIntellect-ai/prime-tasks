#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    python3 -c '
import os

def create_dummy_elf(filepath, entry_byte):
    data = bytearray(64)
    data[0:4] = b"\x7fELF"
    data[4] = 2
    data[24] = entry_byte
    with open(filepath, "wb") as f:
        f.write(data)

os.makedirs("/home/user/artifacts_in", exist_ok=True)
os.makedirs("/home/user/artifacts_repo", exist_ok=True)

create_dummy_elf("/home/user/artifacts_in/a_first.bin", 0x10)
create_dummy_elf("/home/user/artifacts_in/b_second.bin", 0x20)
create_dummy_elf("/home/user/artifacts_in/c_third.bin", 0x10)
create_dummy_elf("/home/user/artifacts_in/d_active.tmp", 0x30)
create_dummy_elf("/home/user/artifacts_in/f_fourth.bin", 0x20)

with open("/home/user/artifacts_in/e_text.txt", "w") as f:
    f.write("not an elf")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
