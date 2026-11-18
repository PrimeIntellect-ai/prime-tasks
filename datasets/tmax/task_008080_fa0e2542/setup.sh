#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/wait_graph.csv
waiter_tx,holder_tx,resource,wait_time_ms
TX01,TX02,RES_A,150
TX02,TX03,RES_B,200
TX03,TX01,RES_C,120
TX04,TX05,RES_D,110
TX05,TX06,RES_E,300
TX06,TX04,RES_F,250
TX07,TX08,RES_G,50
TX08,TX09,RES_H,150
TX09,TX07,RES_I,200
TX10,TX11,RES_J,150
TX11,TX10,RES_K,150
TX02,TX04,RES_L,150
TX04,TX08,RES_M,150
TX08,TX02,RES_N,150
TX01,TX06,RES_P,150
TX06,TX07,RES_Q,150
TX07,TX01,RES_R,150
TX09,TX10,RES_S,150
TX11,TX12,RES_T,150
TX12,TX09,RES_U,150
TX13,TX14,RES_V,150
TX14,TX13,RES_W,150
TX03,TX06,RES_X,150
TX06,TX08,RES_Y,150
TX08,TX03,RES_Z,150
EOF

    chmod -R 777 /home/user
