#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk sed
    pip3 install pytest

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/test_split_alpha.csv
id,emb_1,emb_2,emb_3
1,0.5,0.1,-0.2
2,0.4,-0.5,0.8
3,0.6,0.2,0.1
4,0.3,-0.1,0.4
EOF

    cat << 'EOF' > /home/user/datasets/test_split_beta.csv
id,emb_1,emb_2,emb_3
1,-1.2,0.4,-0.1
2,0.8,-0.2,0.5
3,1.5,0.1,0.2
4,-1.1,-0.3,0.8
EOF

    cat << 'EOF' > /home/user/datasets/test_split_gamma.csv
id,emb_1,emb_2,emb_3
1,-0.2,0.5,0.3
2,-0.1,-0.2,0.1
3,-0.4,0.3,0.2
4,-0.2,-0.1,0.4
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/datasets
    chmod -R 777 /home/user
