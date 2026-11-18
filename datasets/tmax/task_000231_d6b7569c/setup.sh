#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak-ng
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    espeak-ng -w /app/voicemail.wav "Hey, it's Dave. I've set up the new manifest system. The magic header string you need to look for is AQUAMARINE_WHALE. Make sure to block any paths trying to escape the directory."

    cat << 'EOF' > /app/corpora/clean/clean1.txt
HEADER AQUAMARINE_WHALE
FILE: src/main.c
CHUNKS: 2
CHECKSUM: 12345
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.txt
HEADER AQUAMARINE_WHALE
FILE: some/deep/dir/file.txt
CHUNKS: 1
CHECKSUM: abcde
EOF

    cat << 'EOF' > /app/corpora/evil/evil1.txt
HEADER BLUE_WHALE
FILE: src/main.c
CHUNKS: 2
CHECKSUM: 12345
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.txt
HEADER AQUAMARINE_WHALE
FILE: /etc/passwd
CHUNKS: 2
CHECKSUM: 12345
EOF

    cat << 'EOF' > /app/corpora/evil/evil3.txt
HEADER AQUAMARINE_WHALE
FILE: ../../root/.bashrc
CHUNKS: 2
CHECKSUM: 12345
EOF

    cat << 'EOF' > /app/corpora/evil/evil4.txt
HEADER AQUAMARINE_WHALE
FILE: src/../../bin/bash
CHUNKS: 2
CHECKSUM: 12345
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
