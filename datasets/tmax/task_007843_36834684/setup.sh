#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils grep sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.tsv
S1	ATGCATGC	1.0,2.0,3.5,4.0
S2	AAAAAAAA	1.0,2.0,3.0
S3	ATGCATGC	1.0,NaN,3.0
S4	ATGCATGC	1.0,100.0,3.0
S5	ATGCATAGCA	2.0,4.0,5.0
S6	ATGCATGC	0.0,1.0,1.0
S7	ATGCATGCATGCATGC	-5.0,0.0,5.0,10.0,15.0
S8	ATGCCCGGGG	1.0,2.0,3.0
EOF

    cat << 'EOF' > /tmp/expected_features.tsv
S1	8.000	0.000
S5	7.500	0.150
S6	1.500	0.000
S7	20.000	0.000
EOF

    chmod -R 777 /home/user
    chmod 777 /tmp/expected_features.tsv
