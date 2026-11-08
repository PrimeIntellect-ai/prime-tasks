#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/cmdb_exports

    cat << 'EOF' > /tmp/week1.csv
Timestamp,Server1,Server2,Server3
2023-10-01T10:00:00Z,Actif,Actif,Dégradé
2023-10-01T11:00:00Z,Actif,Inactif,Actif
EOF

    iconv -f UTF-8 -t ISO-8859-1 /tmp/week1.csv > /home/user/cmdb_exports/week1.csv

    cat << 'EOF' > /home/user/cmdb_exports/week2.csv
Timestamp,Server1,Server2,Server3
2023-10-02T10:00:00Z,Actif,Actif,Actif
EOF

    chown -R user:user /home/user/cmdb_exports
    chmod -R 777 /home/user
