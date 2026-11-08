#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the raw_events.csv file
    cat << 'EOF' > /home/user/raw_events.csv
raw_ts,usr,req_path,bytes,node_id
1000,u1,/App/Login/,500,n1
1002,u1,/app/login,500,n2
1970-01-01T00:16:45Z,u2,/Data,300,n1
1010,u1,/App/Login,400,n1
1061,u3,/Index,200,n3
1970-01-01T00:17:50Z,u1,/app/login,600,n2
1071,u2,/data/,150,n1
EOF

    # Set permissions
    chmod -R 777 /home/user
