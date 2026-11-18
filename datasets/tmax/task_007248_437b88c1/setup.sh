#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils libc-bin
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/legacy_utf8.csv
2023/10/05 14:00:00,José,jose123@mail.com,203.0.113.42,30,850
2023/10/05 15:30:00,María,maria.b@test.org,198.51.100.7,17,900
2023/10/06 09:15:00,René,rene99@domain.net,192.168.1.250,45,-50
2023/10/06 10:00:00,François,fran@paris.fr,10.0.0.5,101,500
2023/10/07 11:20:00,Günther,gunther@berlin.de,172.16.0.4,60,1000
EOF

    iconv -f UTF-8 -t ISO-8859-1 /home/user/data/legacy_utf8.csv > /home/user/data/legacy.csv
    rm /home/user/data/legacy_utf8.csv

    cat << 'EOF' > /home/user/data/app.csv
2023-10-04T08:00:00Z,Alice,alice.smith@corp.com,8.8.8.8,25,750
2023-10-05T14:15:00Z,Bob,bob_jones@startup.io,1.1.1.1,40,1001
2023-10-06T12:00:00Z,Charlie,charlie@web.com,8.8.4.4,18,0
2023-10-08T16:45:00Z,Diana,diana@cloud.net,203.0.113.199,29,555
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
