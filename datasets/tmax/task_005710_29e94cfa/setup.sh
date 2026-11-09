#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts
    cd /home/user/artifacts

    cat << 'EOF' > temp_A.txt
[STATE: OK] artifact X-101 initialized
[STATE: CORRUPTED] artifact X-102 checksum failed
[STATE: OK] artifact X-103 initialized
EOF

    cat << 'EOF' > temp_B.txt
[STATE: CORRUPTED] artifact Y-201 invalid header
[STATE: OK] artifact Y-202 initialized
EOF

    cat << 'EOF' > temp_C.txt
[STATE: OK] artifact Z-301 initialized
[STATE: OK] artifact Z-302 initialized
EOF

    iconv -f UTF-8 -t UTF-16LE temp_A.txt | gzip > build_node_1.log.gz
    iconv -f UTF-8 -t ISO-8859-1 temp_B.txt | gzip > build_node_2.log.gz
    iconv -f UTF-8 -t UTF-8 temp_C.txt | gzip > build_node_3.log.gz

    cat << 'EOF' > encoding_manifest.csv
build_node_1.log.gz,UTF-16LE
build_node_2.log.gz,ISO-8859-1
build_node_3.log.gz,UTF-8
EOF

    rm temp_A.txt temp_B.txt temp_C.txt

    chmod -R 777 /home/user
