#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.tsv
1	25	US
2	30	UK
3	22	CA
4	40	AU
5	35	JP
6	28	BR
7	15.5	MX
8	-5	IN
9	50	DE
10	60	FR
EOF

    cat << 'EOF' > /home/user/data/predictions.tsv
1	M1	0.85
2	M1	1.20
3	M2	0.50
4	M2	0.45
5	M2	0.99
6	M3	0.40
7	M3	0.55
8	M1	0.10
9	M4	-0.05
10	M4	0.88
EOF

    cat << 'EOF' > /home/user/data/latency.tsv
1	120
2	110
3	-10
4	130
5	150
7	100
8	140
9	125
10	0
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
