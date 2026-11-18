#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip util-linux coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_inbox
    mkdir -p /home/user/organized_data
    mkdir -p /home/user/latest_data
    mkdir -p /home/user/tmp

    cat << 'EOF' > /home/user/project_inbox/extract_001.dat
ID:GAMMA VER:3
Data for gamma 3
EOF

    cat << 'EOF' > /home/user/project_inbox/.._.._badpath.dat
ID:GAMMA VER:1
Data for gamma 1
EOF

    cat << 'EOF' > /home/user/project_inbox/random_name.dat
ID:OMEGA VER:10
Data for omega 10
EOF

    cat << 'EOF' > /home/user/project_inbox/omega_old.dat
ID:OMEGA VER:2
Data for omega 2
EOF

    cat << 'EOF' > /home/user/project_inbox/readme.txt
ID:BETA VER:99
This is just a readme.
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
