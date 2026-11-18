#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest numpy

    mkdir -p /home/user/drift_data

    cat << 'EOF' > /home/user/drift_data/server_alpha.csv
timestamp,drift_score
100,5.0
101,6.0
102,7.0
103,10.0
104,15.0
105,12.0
106,8.0
107,5.0
108,6.0
EOF

    cat << 'EOF' > /home/user/drift_data/server_beta.csv
timestamp,drift_score
200,1.0
201,1.5
202,2.0
203,1.8
204,1.9
205,2.0
EOF

    cat << 'EOF' > /home/user/drift_data/server_gamma.csv
timestamp,drift_score
300,10.0
301,10.0
302,10.0
303,20.0
304,30.0
305,40.0
306,40.0
307,40.0
EOF

    cat << 'EOF' > /home/user/drift_data/server_delta.csv
timestamp,drift_score
400,1.0
401,1.0
402,1.0
403,1.0
404,1.0
405,1.0
406,1.0
407,1.0
408,1.0
409,20.0
410,20.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
