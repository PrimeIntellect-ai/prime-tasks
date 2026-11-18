#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_files/libs
    mkdir -p /home/user/organized_routes

    cat << 'EOF' > /home/user/project_files/libs/libauth.c
void route_handler() {}
EOF

    cat << 'EOF' > /home/user/project_files/libs/libdata.c
void wrong_handler() {}
EOF

    cat << 'EOF' > /home/user/project_files/libs/libuser.c
void route_handler() {}
EOF

    gcc -shared -fPIC /home/user/project_files/libs/libauth.c -o /home/user/project_files/libs/libauth.so
    gcc -shared -fPIC /home/user/project_files/libs/libdata.c -o /home/user/project_files/libs/libdata.so
    gcc -shared -fPIC /home/user/project_files/libs/libuser.c -o /home/user/project_files/libs/libuser.so

    MD5_AUTH=$(md5sum /home/user/project_files/libs/libauth.so | awk '{print $1}')
    MD5_DATA=$(md5sum /home/user/project_files/libs/libdata.so | awk '{print $1}')
    MD5_USER=$(md5sum /home/user/project_files/libs/libuser.so | awk '{print $1}')

    cat << EOF > /home/user/project_files/routes.conf
ROUTE /api/v1/auth?token=str&user=int => libauth.so : $MD5_AUTH
ROUTE /api/v1/data?id=int => libdata.so : $MD5_DATA
ROUTE /api/v2/user => libuser.so : 00000000000000000000000000000000
ROUTE /api/v2/settings => libmiss.so : 11111111111111111111111111111111
EOF

    cat << 'EOF' > /home/user/legacy_parser.py
import re
with open('/home/user/project_files/routes.conf', 'r') as f:
    for line in f:
        match = re.match(r'ROUTE\s+([^?\s]+)[^\s]*\s+=>\s+(\S+)\s+:\s+(\S+)', line)
        if match:
            print(f"Path: {match.group(1)}, Lib: {match.group(2)}")
EOF

    chmod -R 777 /home/user
