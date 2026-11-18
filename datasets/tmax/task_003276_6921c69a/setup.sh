#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/baseline.csv
id,true_label,pred_label,pca1,pca2
1,1,1,0.5,0.1
2,0,0,0.2,0.9
3,1,0,0.8,0.3
4,0,1,0.1,0.4
5,1,1,0.9,0.2
6,0,0,0.3,0.3
7,1,1,0.4,0.4
8,0,0,0.5,0.5
9,1,1,0.6,0.6
10,0,0,0.7,0.7
EOF

    cat << 'EOF' > /home/user/new_model.csv
id,true_label,pred_label,pca1,pca2
1,1,1,0.5,0.1
2,0,0,0.2,0.9
3,1,1,0.8,0.3
4,0,0,0.1,0.4
5,1,1,0.9,0.2
6,0,0,0.3,0.3
7,1,1,0.4,0.4
8,0,0,0.5,0.5
9,1,1,0.6,0.6
10,0,0,0.7,0.7
EOF

    chmod -R 777 /home/user
