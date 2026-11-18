#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/mesh_graph.tsv
Node_1	Node_2	15
Node_2	Node_3	42
Node_10	Node_12	88
Node_73	Node_128	500
Node_50	Node_60	112
Node_1	Node_10	12
EOF

    cat << 'EOF' > /home/user/primers.tsv
Node_1	AAAAAAAAAA
Node_2	AAAAAATAAA
Node_3	TTTTTTTTTT
Node_10	CCCCCCCCCC
Node_12	CGCCCCCCCC
Node_50	GGGGGGGGGG
Node_60	GGGGGGGGGG
Node_73	ACGTACGTAC
Node_128	ACCTACGGAC
EOF

    chmod 644 /home/user/mesh_graph.tsv /home/user/primers.tsv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
