#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip file tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/recovery/inbox
    mkdir -p /home/user/recovery/organized

    # 1. PNG Image (older than backup)
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==" | base64 -d > /home/user/recovery/inbox/file1.dat
    touch -d "2023-01-01 10:00:00" /home/user/recovery/inbox/file1.dat

    # Create backup stamp
    touch -d "2023-01-01 12:00:00" /home/user/recovery/last_backup.stamp

    # 2. PDF Document (newer than backup)
    echo "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF" > /home/user/recovery/inbox/file2.bin
    touch -d "2023-01-02 10:00:00" /home/user/recovery/inbox/file2.bin

    # 3. Text file (newer than backup)
    echo "This is a plain text recovery file." > /home/user/recovery/inbox/file3.tmp
    touch -d "2023-01-03 10:00:00" /home/user/recovery/inbox/file3.tmp

    # 4. GZIP file (newer than backup)
    echo "dummy data" | gzip > /home/user/recovery/inbox/file4.bak
    touch -d "2023-01-04 10:00:00" /home/user/recovery/inbox/file4.bak

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
