#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph.csv
A:Actor1,M:Movie1
D:Dir1,M:Movie1
A:Actor2,M:Movie1
A:Actor2,M:Movie2
D:Dir2,M:Movie2
A:Actor3,M:Movie3
D:Dir3,M:Movie3
M:Movie1,A:Actor4
M:Movie4,D:Dir1
M:Movie5,D:Dir1
M:Movie6,D:Dir1
M:Movie7,D:Dir1
M:Movie8,D:Dir1
M:Movie9,D:Dir1
M:Movie10,D:Dir1
A:Actor5,M:Movie10
A:Actor5,M:Movie11
A:Actor5,M:Movie12
A:Actor5,M:Movie13
A:Actor5,M:Movie14
EOF

    chmod -R 777 /home/user
