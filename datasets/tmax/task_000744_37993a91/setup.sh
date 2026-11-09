#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/packages.csv
pkg_id,pkg_name
1,AuthModule
2,DBConnector
3,Logger
4,Utils
5,CryptoLib
6,NetworkStack
7,WebApp
8,CacheManager
EOF

    cat << 'EOF' > /home/user/data/dependencies.csv
pkg_id,depends_on_pkg_id
7,1
7,2
7,8
1,5
1,4
2,6
2,3
2,4
6,5
6,3
8,4
EOF

    cat << 'EOF' > /home/user/data/vulnerabilities.csv
pkg_id,vulnerability_score
1,5
3,2
4,1
5,10
6,8
7,0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
