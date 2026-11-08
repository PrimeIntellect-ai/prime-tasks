#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rsync gawk
    pip3 install pytest

    mkdir -p /opt/staging_server/data/

    cat << 'EOF' > /opt/staging_server/data/batch1.csv
id,name,date,country
101,  Alice Smith  ,05/12/2023, us 
103,Bob Jones,2023-04-10,Uk
invalid,Drop Me,01/01/2020,CA
102, Charlie ,12/31/2022, fr
EOF

    cat << 'EOF' > /opt/staging_server/data/batch2.csv
id,name,date,country
201,Diana,01/05/2023, DE 
202, Evan ,2023-06-15, au
EOF

    chmod -R 755 /opt/staging_server

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
