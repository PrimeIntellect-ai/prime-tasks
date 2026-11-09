#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/archive_temp/docs/api
    mkdir -p /home/user/archive_temp/docs/misc

    # Create v1.txt (exactly 28 bytes)
    printf "API Version 1\nLine 2 is here." > /home/user/archive_temp/docs/api/v1.txt

    # Create readme.txt (exactly 28 bytes)
    printf "General Readme\nHello world!" > /home/user/archive_temp/docs/misc/readme.txt

    # Create notes.txt (exactly 28 bytes, but we will put a wrong size in the config)
    printf "Developer Notes\nSome notes." > /home/user/archive_temp/docs/notes.txt

    # Create setup.bin (binary, 128 bytes)
    dd if=/dev/urandom of=/home/user/archive_temp/docs/setup.bin bs=1 count=128 status=none

    # Create doc_map.ini
    cat << 'EOF' > /home/user/archive_temp/doc_map.ini
[Docs]
file1=docs/api/v1.txt|28
file2=docs/setup.bin|128
file3=docs/notes.txt|999
file4=docs/misc/readme.txt|28
EOF

    # Create the archive
    cd /home/user/archive_temp
    tar -czf /home/user/incoming_docs.tar.gz .
    cd /home/user
    rm -rf /home/user/archive_temp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
