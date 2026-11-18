#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/observational_data.tsv
seq_id	time_idx	signal
A	0	1.0
A	1	1.0
A	2	1.0
A	3	1.0
A	4	1.0
A	5	1.0
A	6	1.0
A	7	1.0
B	0	10.0
B	1	7.0710678
B	2	0.0
B	3	-7.0710678
B	4	-10.0
B	5	-7.0710678
B	6	0.0
B	7	7.0710678
C	0	0.0
C	1	7.0710678
C	2	10.0
C	3	7.0710678
C	4	0.0
C	5	-7.0710678
C	6	-10.0
C	7	-7.0710678
D	0	2.0
D	2	2.0
D	4	2.0
D	6	2.0
EOF

    chmod -R 777 /home/user
