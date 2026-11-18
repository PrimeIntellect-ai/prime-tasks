#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Levenshtein

    mkdir -p /home/user/raw_configs/

    # File 1: alpha.conf (UTF-8)
    cat << 'EOF' > /home/user/raw_configs/alpha.conf
# Main config
host=localhost
port=8080
EOF

    # File 2: beta.conf (UTF-16LE)
    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > /home/user/raw_configs/beta.conf
# Beta config
host = localhost
port= 8080
EOF

    # File 3: gamma.cfg (ISO-8859-1)
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/raw_configs/gamma.cfg
# DB config
db_host=192.168.1.1
db_pass=supersecrët
EOF

    # File 4: delta.cfg (UTF-8)
    cat << 'EOF' > /home/user/raw_configs/delta.cfg
db_host=192.168.1.1
db_pass=supersecrët
EOF

    # File 5: epsilon.cfg (UTF-8)
    cat << 'EOF' > /home/user/raw_configs/epsilon.cfg
# unrelated
something_else=true
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
