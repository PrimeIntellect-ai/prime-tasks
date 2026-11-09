#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/nodes.csv
id,name,type
N1,StationA,Hub
N2,StationB,Hub
N3,StationC,Maintenance
N4,StationD,Normal
N5,StationE,Normal
N6,StationF,Normal
N7,StationG,Normal
N8,StationH,Normal
EOF

    cat << 'EOF' > /home/user/data/edges.csv
src,dst,cost
N1,N2,10
N2,N4,15
N1,N3,5
N3,N4,5
N4,N5,10
N5,N6,10
N1,N7,30
N7,N8,10
EOF

    chmod -R 777 /home/user
