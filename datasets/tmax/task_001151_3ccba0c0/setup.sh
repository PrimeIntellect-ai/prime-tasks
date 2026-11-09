#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/inputs

    cat << 'EOF' > /home/user/inputs/file1.csv
id,locale,source_text,target_text,rate_per_char
1,es,"Hello","Hola",0.05
2,fr,"Line 1
Line2","Ligne 1
Ligne 2",0.06
3,de,"Short","This is way too long for just short",0.10
4,es,"Missing target","",0.05
EOF

    cat << 'EOF' > /home/user/inputs/file2.csv
id,locale,source_text,target_text,rate_per_char
5,es,"Welcome
User","Bienvenido
Usuario",0.05
6,fr,"One","Un",0.06
EOF

    chmod -R 777 /home/user
