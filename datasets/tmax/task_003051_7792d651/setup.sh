#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs('/home/user/data', exist_ok=True)

nodes = []
for i in range(1, 101):
    if i in [10, 20, 30, 40, 50]:
        role = 'Manager'
    elif i in [5, 15, 25]:
        role = 'Director'
    elif i < 50:
        role = 'Engineer'
    else:
        role = 'Analyst'

    dept = 'Engineering' if i <= 50 else 'Sales'
    nodes.append(f"{i},{role},{dept}\n")

with open('/home/user/data/graph_y.csv', 'w') as f:
    f.writelines(nodes)

edges = []
edges.append("1000000,10,1\n")
edges.append("1001000,5,10\n")
edges.append("1000500,10,2\n")
edges.append("1002000,15,10\n")
edges.append("1003000,10,3\n")
edges.append("1004000,5,10\n")
edges.append("1005000,10,4\n")
edges.append("1006000,25,10\n")
edges.append("1007000,10,6\n")
edges.append("1008000,5,10\n")

edges.append("1010000,20,7\n")
edges.append("1011000,15,20\n")
edges.append("1012000,20,8\n")
edges.append("1013000,25,20\n")
edges.append("1014000,20,9\n")
edges.append("1015000,5,20\n")
edges.append("1016000,20,11\n")
edges.append("1017000,15,20\n")

edges.append("1020000,30,12\n")
edges.append("1021000,5,30\n")
edges.append("1022000,30,13\n")
edges.append("1023000,15,30\n")

edges.append("1030000,40,14\n")
edges.append("1031000,5,40\n")
edges.append("1032000,40,16\n")
edges.append("1033000,25,40\n")

edges.append("1040000,50,17\n")
edges.append("1044000,5,50\n")

edges.append("1050000,18,50\n")

with open('/home/user/data/graph_x.csv', 'w') as f:
    f.writelines(edges)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
