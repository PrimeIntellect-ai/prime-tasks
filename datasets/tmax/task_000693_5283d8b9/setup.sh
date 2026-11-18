#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user/sim_data

    cat << 'EOF' > /home/user/sim_data/network.json
{
  "N_0": {"N_1": 1.2, "N_2": 2.5},
  "N_1": {"N_2": 0.6, "N_3": 3.0},
  "N_2": {"N_3": 1.1},
  "N_3": {}
}
EOF

    cat << 'EOF' > /home/user/sim_data/signals.csv
time,N_0,N_1,N_2,N_3
0,1.0,0.0,-1.0,2.0
1,2.0,1.0,0.0,0.0
2,1.0,2.0,1.0,-2.0
3,0.0,1.0,2.0,0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
