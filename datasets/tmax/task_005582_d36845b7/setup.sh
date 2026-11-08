#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
id,name
N001,Alice
N002,Bob
N003,Charlie
N004,Diana
N005,Eve
N006,Frank
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,weight
N001,N002,1.5
N002,N003,2.5
N001,N004,2.0
N004,N005,3.0
N004,N003,4.0
N001,N006,0.5
N006,N005,1.0
EOF

    chmod -R 777 /home/user
