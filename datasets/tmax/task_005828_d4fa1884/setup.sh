#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_alpha.csv
item_id_alpha,f1,f2,f3
A01,1.0,0.0,0.0
A02,0.0,1.0,0.0
A03,0.7071,0.7071,0.0
A04,0.5,0.5,0.7071
A05,0.0,0.0,1.0
EOF

    cat << 'EOF' > /home/user/system_beta.csv
item_id_beta,f1,f2,f3
B01,0.9,0.1,0.0
B02,0.1,0.9,0.0
B03,0.0,0.1,0.9
B04,0.4,0.6,0.6928
B05,0.8,0.0,0.0
EOF

    chmod -R 777 /home/user
