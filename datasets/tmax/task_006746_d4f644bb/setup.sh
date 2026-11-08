#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/incident
    cd /home/user/incident

    # Generate traffic_dump.txt
    cat << 'EOF' > traffic_dump.txt
12:00:00.001 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.002 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.003 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.004 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.005 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.006 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.007 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.008 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.009 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.010 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.1}

12:00:00.011 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.14}

12:00:00.012 IP 10.0.0.1 > 10.0.0.2: Flags [P.]
POST /api/metrics HTTP/1.1
Content-Type: application/json
{"account_id":"ACC-999","amount":0.28}

EOF

    # Generate db_queries.log (dropping two 0.1 updates)
    cat << 'EOF' > db_queries.log
[12:00:00.002] UPDATE balances SET total = total + 0.1 WHERE account_id = 'ACC-999';
[12:00:00.003] UPDATE balances SET total = total + 0.1 WHERE account_id = 'ACC-999';
[12:00:00.004] UPDATE balances SET total = total + 0.1 WHERE account_id = 'ACC-999';
[12:00:00.006] UPDATE balances SET total = total + 0.1 WHERE account_id = 'ACC-999';
[12:00:00.007] UPDATE balances SET total = total + 0.1 WHERE account_id = 'ACC-999';
[12:00:00.008] UPDATE balances SET total = total + 0.1 WHERE account_id = 'ACC-999';
[12:00:00.009] UPDATE balances SET total = total + 0.1 WHERE account_id = 'ACC-999';
[12:00:00.010] UPDATE balances SET total = total + 0.1 WHERE account_id = 'ACC-999';
[12:00:00.012] UPDATE balances SET total = total + 0.14 WHERE account_id = 'ACC-999';
[12:00:00.013] UPDATE balances SET total = total + 0.28 WHERE account_id = 'ACC-999';
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
