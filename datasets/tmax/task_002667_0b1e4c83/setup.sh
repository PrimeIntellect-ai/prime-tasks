#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    # Create directories
    mkdir -p /app/localization
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create dummy reference audio file
    # A simple empty file is enough to pass the initial state test
    touch /app/localization/reference_sync.wav

    # Create clean CSV files
    cat << 'EOF' > /app/corpora/clean/clean1.csv
key,timestamp,en,es,fr,de
KEY 1,0,en1,es1,fr1,de1
KEY 2,1,en2,es2,fr2,de2
KEY 3,2,en3,es3,fr3,de3
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.csv
key,timestamp,en,es,fr,de
KEY 4,0,en4,es4,fr4,de4
EOF

    # Create evil CSV files
    cat << 'EOF' > /app/corpora/evil/evil_xss.csv
key,timestamp,en,es,fr,de
KEY 1,0,en1,<script>alert(1)</script>,fr1,de1
EOF

    cat << 'EOF' > /app/corpora/evil/evil_missing.csv
key,timestamp,en,es,fr,de
KEY 1,0,en1,,fr1,de1
EOF

    cat << 'EOF' > /app/corpora/evil/evil_timestamp.csv
key,timestamp,en,es,fr,de
KEY 1,3,en1,es1,fr1,de1
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
