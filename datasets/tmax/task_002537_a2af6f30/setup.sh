#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifact_repo

    # Create standard binary files
    printf "\x89\x50\x4E\x47\x0D\x0A\x1A\x0A" > /home/user/artifact_repo/image.png
    printf "\xCA\xFE\xBA\xBE\x00\x00\x00\x32" > /home/user/artifact_repo/java.class
    printf "\x7F\x45\x4C\x46\x02\x01\x01\x00" > /home/user/artifact_repo/binary.elf

    # Create symlink loops
    ln -s /home/user/artifact_repo/loop2.bin /home/user/artifact_repo/loop1.bin
    ln -s /home/user/artifact_repo/loop1.bin /home/user/artifact_repo/loop2.bin

    # Create the ISO-8859-1 encoded log file using Python to ensure correct encoding
    python3 -c '
content = """RECORD_START
Target: /home/user/artifact_repo/image.png
Info: Standard image file with naïve metadata.
RECORD_END
RECORD_START
Target: /home/user/artifact_repo/loop1.bin
Info: Corrupted reference pointing to a recursive tree.
RECORD_END
RECORD_START
Target: /home/user/artifact_repo/java.class
Info: Compiled bytecode.
RECORD_END
RECORD_START
Target: /home/user/artifact_repo/missing_file.dat
Info: File deleted but log persists.
RECORD_END
RECORD_START
Target: /home/user/artifact_repo/binary.elf
Info: Executable object.
RECORD_END
"""
with open("/home/user/artifact_repo/sync_log.txt", "w", encoding="ISO-8859-1") as f:
    f.write(content)
'

    chmod -R 777 /home/user
