#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate DBA memo
    espeak -w /app/dba_memo.wav "A valid backup manifest must have all nodes eventually trace back to the root node named 'MASTER'. Any manifest that contains a node named 'CORRUPT' is invalid. Lastly, no manifest can have a dependency cycle."

    # Create clean manifests
    cat << 'EOF' > /app/corpus/clean/clean1.txt
backup1 MASTER
backup2 backup1
backup3 backup2
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.txt
nodeA MASTER
nodeB nodeA
nodeC nodeA
EOF

    # Create evil manifests
    # 1. Contains CORRUPT
    cat << 'EOF' > /app/corpus/evil/evil_corrupt.txt
backup1 MASTER
backup2 CORRUPT
EOF

    # 2. Cycle
    cat << 'EOF' > /app/corpus/evil/evil_cycle.txt
backup1 MASTER
backup2 backup3
backup3 backup2
EOF

    # 3. Does not trace to MASTER
    cat << 'EOF' > /app/corpus/evil/evil_no_master.txt
backup1 OTHER_ROOT
backup2 backup1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
