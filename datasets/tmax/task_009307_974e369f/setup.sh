#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_data

    cat << 'EOF' > /home/user/backup_data/nodes.csv
1,Engineer,Alice
2,Engineer,Bob
3,Cluster,ClusterAlpha
4,Cluster,ClusterBeta
5,Database,DB_Payments
6,Database,DB_Analytics
7,Database,DB_Users
8,Storage,S3_Backup_Bucket
9,Engineer,Charlie
10,Cluster,ClusterGamma
11,Database,DB_Logs
EOF

    cat << 'EOF' > /home/user/backup_data/edges.csv
1,MANAGES,3
2,MANAGES,4
9,MANAGES,10
3,HOSTS,5
4,HOSTS,6
4,HOSTS,7
10,HOSTS,11
5,HAS_BACKUP,8
6,HAS_BACKUP,8
99,MANAGES,3
4,HOSTS,88
10,HAS_BACKUP,8
EOF

    chmod -R 777 /home/user
