#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/networks
    mkdir -p /home/user/graph_compare

    cat << 'EOF' > /home/user/node_types.csv
node_id,type
1,A
2,A
3,C
4,B
5,B
EOF

    cat << 'EOF' > /home/user/networks/graph_1.txt
1 3
2 3
3 4
3 5
EOF

    cat << 'EOF' > /home/user/networks/graph_2.txt
1 4
2 3
3 5
EOF

    cat << 'EOF' > /home/user/reference_dist.json
{
  "1": 0.2,
  "2": 0.8
}
EOF

    chmod -R 777 /home/user
