#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
1,Alice
2,Bob
3,Charlie
4,Dave
5,Eve
6,Frank
EOF

    cat << 'EOF' > /home/user/data/follows.csv
1,3
2,4
5,3
1,2
6,1
EOF

    cat << 'EOF' > /home/user/data/posts.csv
101,3,I think BASH_ROCKS a lot
102,4,Python is okay
103,2,I agree BASH_ROCKS too
104,1,Just setting up my twttr
EOF

    chmod -R 777 /home/user
