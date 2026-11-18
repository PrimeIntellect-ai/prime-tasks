#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev gzip
    pip3 install pytest

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/processed

    cat << 'EOF' > /home/user/rules.conf
alpha.gz:5
beta.gz:10
gamma.gz:15
delta.gz:20
EOF

    # Create alpha.gz (Valid, 5 lines)
    echo -e "line1\nline2\nline3\nline4\nline5" | gzip > /home/user/raw_data/alpha.gz

    # Create beta.gz (Corrupt gzip archive)
    echo "Not a valid gzip file at all" > /home/user/raw_data/beta.gz

    # Create gamma.gz (Valid gzip, but 10 lines instead of 15)
    echo -e "1\n2\n3\n4\n5\n6\n7\n8\n9\n10" | gzip > /home/user/raw_data/gamma.gz

    # Create delta.gz (Valid, 20 lines)
    for i in $(seq 1 20); do echo "data_line_$i"; done | gzip > /home/user/raw_data/delta.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
