#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/valid_1.csv
1,2
3,4
-5,6
EOF

    cat << 'EOF' > /home/user/datasets/valid_na.csv
10,2
NA,5
-3,NA
4,4
EOF

    cat << 'EOF' > /home/user/datasets/invalid_cols.csv
1,2,3
4,5,6
EOF

    cat << 'EOF' > /home/user/datasets/invalid_chars.csv
1,2
3,a
4,5
EOF

    cat << 'EOF' > /home/user/datasets/invalid_floats.csv
1.5,2
3,4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
