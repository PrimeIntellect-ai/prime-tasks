#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/papers.csv
id,title,year
A,Paper A,2000
B,Paper B,2001
C,Paper C,2002
D,Paper D,2003
E,Paper E,2004
F,Paper F,2005
EOF

    cat << 'EOF' > /home/user/citations.csv
citer_id,cited_id
A,B
A,C
B,D
C,D
D,E
C,F
F,E
EOF

    chmod -R 777 /home/user
