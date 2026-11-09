#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_logs.csv
timestamp,src_node,dst_node,action
1000,U_01,DB_A,READ
1005,U_01,EXT_Z,TRANSFER
1001,U_02,DB_B,READ
1006,U_02,EXT_Y,TRANSFER
1002,U_03,DB_A,READ
1008,U_03,EXT_Z,TRANSFER
1003,U_04,DB_C,READ
1010,U_04,EXT_X,TRANSFER
1004,U_05,DB_A,READ
1005,U_05,EXT_W,TRANSFER
1005,U_06,DB_B,READ
1009,U_06,EXT_V,TRANSFER
999,U_99,DB_A,WRITE
1000,U_99,EXT_Z,TRANSFER
EOF

    chmod -R 777 /home/user
