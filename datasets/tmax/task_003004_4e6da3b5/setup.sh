#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils findutils gawk gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Setup directories
    mkdir -p /home/user/incoming/archives
    mkdir -p /home/user/curated

    # Create test data
    mkdir -p /tmp/build_101 /tmp/build_102 /tmp/build_103 /tmp/build_104
    echo "common_binary_data" > /tmp/common.bin
    echo "unique_101" > /tmp/build_101/app.bin
    echo "unique_102" > /tmp/build_102/app.bin
    echo "unique_103" > /tmp/build_103/app.bin
    echo "unique_104" > /tmp/build_104/app.bin

    for i in 101 102 103 104; do
        cp /tmp/common.bin /tmp/build_$i/lib.so
        tar -cf /home/user/incoming/archives/build_$i.tar -C /tmp/build_$i .
    done

    # Create log file
    cat << 'EOF' > /home/user/incoming/builds.log
--- BUILD 101 ---
Compiling main...
Linking...
STATUS: SUCCESS
--- BUILD 102 ---
Compiling main...
Error: missing header
STATUS: FAILURE
--- BUILD 103 ---
Compiling main...
Linking...
STATUS: SUCCESS
--- BUILD 104 ---
Compiling main...
Error: segfault in compiler
STATUS: FAILURE
EOF

    # Create initial tar state to test incremental backup
    mkdir -p /home/user/curated/dummy
    echo "old" > /home/user/curated/dummy/old.txt
    tar --listed-incremental=/home/user/backup.snar -czf /home/user/old_backup.tar.gz -C /home/user curated/dummy 2>/dev/null
    rm -rf /home/user/curated/dummy

    chown -R user:user /home/user/incoming /home/user/curated /home/user/backup.snar /home/user/old_backup.tar.gz || true
    chmod -R 777 /home/user
