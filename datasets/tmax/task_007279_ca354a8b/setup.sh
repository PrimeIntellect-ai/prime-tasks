#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_telemetry.csv
1700000000,S1,10.5,ok
1700000100,S1,11.5,ok
1700001000,S2,20.0,testing
1700001500,S2,22.0,newline
in
notes
1700003500,S1,12.5,ok
1700004000,S1,15.0,next_hour
1700004500,S2,10.0,ok
1700005000,S1,16.5,ok
1700000500,S3,100.0,bad,extra,column
1700000500,S3,105.0,ok
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
