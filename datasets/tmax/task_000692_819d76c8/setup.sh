#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq tar findutils coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_volume/dir_A
    mkdir -p /home/user/data_volume/dir_B/sub_C
    mkdir -p "/home/user/data_volume/dir D"

    # File 1: Old, no lock, archivable -> SHOULD BE ARCHIVED
    cat << 'EOF' > /home/user/data_volume/dir_A/file1.json
{"id": 1, "status": "archivable", "data": "content A"}
EOF
    touch -d "40 days ago" /home/user/data_volume/dir_A/file1.json

    # File 2: Old, HAS lock, archivable -> SKIP (Locked)
    cat << 'EOF' > /home/user/data_volume/dir_A/file2.json
{"id": 2, "status": "archivable", "data": "content B"}
EOF
    touch -d "45 days ago" /home/user/data_volume/dir_A/file2.json
    touch /home/user/data_volume/dir_A/file2.json.lock

    # File 3: New, no lock, archivable -> SKIP (Not old enough)
    cat << 'EOF' > /home/user/data_volume/dir_B/sub_C/file3.json
{"id": 3, "status": "archivable", "data": "content C"}
EOF
    touch -d "10 days ago" /home/user/data_volume/dir_B/sub_C/file3.json

    # File 4: Old, no lock, active -> SKIP (Wrong status)
    cat << 'EOF' > /home/user/data_volume/dir_B/sub_C/file4.json
{"id": 4, "status": "active", "data": "content D"}
EOF
    touch -d "50 days ago" /home/user/data_volume/dir_B/sub_C/file4.json

    # File 5: Old, no lock, archivable, path with spaces -> SHOULD BE ARCHIVED
    cat << 'EOF' > "/home/user/data_volume/dir D/file 5.json"
{"id": 5, "status": "archivable", "data": "content E"}
EOF
    touch -d "60 days ago" "/home/user/data_volume/dir D/file 5.json"

    chown -R user:user /home/user/data_volume
    chmod -R 777 /home/user
