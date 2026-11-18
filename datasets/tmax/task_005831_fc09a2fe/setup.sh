#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/citation_graph.csv
edge_id,child,parent,timestamp,is_active
1,A,ROOT,100,1
2,B,ROOT,110,1
3,C,ROOT,100,1
4,D,ROOT,105,1
5,B,ROOT,90,0
6,E,A,120,1
7,F,A,125,1
8,G,B,130,1
9,H,B,135,1
10,I,C,140,1
11,J,C,145,1
12,K,D,150,1
13,L,D,155,1
14,M,E,160,1
15,N,E,165,1
16,O,F,170,1
17,P,F,175,1
18,Q,G,180,1
19,R,G,185,1
20,S,H,190,1
21,T,H,195,1
22,U,I,200,1
23,V,I,205,1
24,W,J,210,1
25,X,J,215,1
26,Y,K,220,1
27,Z,K,225,1
28,STALE1,ROOT,50,0
29,STALE2,A,60,0
30,C,ROOT,80,1
EOF

    chmod -R 777 /home/user
