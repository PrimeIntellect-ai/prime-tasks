#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cmake
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_dump.txt
[2023-10-01 10:00:00] JOB-A | SEQ:100 | PAYLOAD:AlphaBeta
[2023-10-01 10:01:00] JOB-A | SEQ:101 | PAYLOAD:GammaDelta
[2023-10-01 10:02:00] JOB-A | SEQ:102 | PAYLOAD:EpsilonZeta
[2023-10-01 10:03:00] JOB-A | SEQ:103 | PAYLOAD:EtaTheta
[2023-10-01 10:05:00] JOB-A | SEQ:102 | PAYLOAD:EpsilomZeta
[2023-10-01 10:06:00] JOB-A | SEQ:103 | PAYLOAD:EtaTheta!
[2023-10-01 10:07:00] JOB-A | SEQ:104 | PAYLOAD:IotaKappa
[2023-10-01 10:08:00] JOB-A | SEQ:105 | PAYLOAD:LambdaMu
EOF

    chmod -R 777 /home/user
