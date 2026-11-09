#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph_nodes.csv
id,type
n1,Bot
n2,User
n3,Post
n4,Bot
n5,User
n6,Post
n7,Bot
n8,User
EOF

    cat << 'EOF' > /home/user/graph_edges.csv
source,target,relation,weight
n1,n2,follows,0.8
n2,n3,likes,0.5
n4,n5,follows,0.9
n5,n6,likes,0.7
n1,n5,follows,0.2
n5,n3,likes,0.1
n7,n8,follows,0.6
n8,n6,likes,0.8
n4,n2,follows,0.4
EOF

    chmod -R 777 /home/user
