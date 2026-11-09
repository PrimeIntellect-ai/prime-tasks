#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_docs

    cat << 'EOF' > /home/user/raw_docs/intro.txt
Welcome to the documentation.

This is the introduction.
It has some vowels.
EOF

    cat << 'EOF' > /home/user/raw_docs/setup.txt
To setup the project:
1. Run make
2. Run make install

Done.
EOF

    cat << 'EOF' > /home/user/raw_docs/advanced.txt

Advanced topics include concurrent access.
Locks are important.

EOF

    chmod -R 777 /home/user
