#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest pandas scikit-learn

    mkdir -p /app

    # Generate a dummy video with varying frame sizes
    ffmpeg -f lavfi -i testsrc=duration=30:size=320x240:rate=30 -c:v libx264 -crf 22 -preset ultrafast /app/traffic.mp4 -y

    # Generate topology.csv
    cat << 'EOF' > /app/topology.csv
node_id,parent_id,region
0,,North
1,0,North
2,0,North
3,1,North
4,2,North
5,,South
6,5,South
7,6,South
8,,East
9,8,East
10,8,East
EOF

    # Expand to 500 nodes via python script
    cat << 'EOF' > /tmp/gen_top.py
import random
random.seed(42)
nodes = {i: {'parent': None, 'region': random.choice(['North', 'South', 'East', 'West'])} for i in range(11)}
# Keep 0, 5, 8 as roots
roots = [0, 5, 8]
for i in range(11, 500):
    parent = random.randint(0, i-1)
    region = nodes[parent]['region'] # inherit region for simplicity, though roots define the top-level region
    nodes[i] = {'parent': parent, 'region': region}

with open('/app/topology.csv', 'w') as f:
    f.write('node_id,parent_id,region\n')
    for i in range(500):
        parent_str = str(nodes[i]['parent']) if nodes[i]['parent'] is not None else ''
        f.write(f"{i},{parent_str},{nodes[i]['region']}\n")
EOF
    python3 /tmp/gen_top.py
    chmod 644 /app/topology.csv
    chmod 644 /app/traffic.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
