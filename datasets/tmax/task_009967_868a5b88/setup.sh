#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/storage_pool/dir_a
    mkdir -p /home/user/storage_pool/dir_b/sub_c

    # Valid file 1 (5 bytes payload)
    printf "BKUP\x05\x00\x00\x0012345" > /home/user/storage_pool/dir_a/backup1.dat

    # Corrupted file 1: Bad magic number
    printf "BxxP\x05\x00\x00\x0012345" > /home/user/storage_pool/dir_a/corrupt_magic.bin

    # Corrupted file 2: Payload too short for header size (Header says 10, actual is 5)
    printf "BKUP\x0A\x00\x00\x0012345" > /home/user/storage_pool/dir_b/short_payload.bak

    # Valid file 2 (0 bytes payload)
    printf "BKUP\x00\x00\x00\x00" > /home/user/storage_pool/dir_b/sub_c/empty_payload.dat

    # Corrupted file 3: Truncated header (only 6 bytes total)
    printf "BKUP\x05\x00" > /home/user/storage_pool/dir_b/sub_c/trunc_header.dat

    # Corrupted file 4: Payload too long for header size (Header says 2, actual is 5)
    printf "BKUP\x02\x00\x00\x0012345" > /home/user/storage_pool/long_payload.archive

    # Valid file 3 (20 bytes payload)
    printf "BKUP\x14\x00\x00\x00abcdefghijklmnopqrst" > /home/user/storage_pool/valid_large.dat

    chown -R user:user /home/user/storage_pool
    chmod -R 777 /home/user
