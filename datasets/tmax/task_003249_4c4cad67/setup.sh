#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/run1_gc.tsv
GC_Fraction	Density
0.0	0.0
0.1	0.4
0.2	1.2
0.3	1.8
0.4	1.6
0.5	1.0
0.6	0.8
0.7	1.2
0.8	1.4
0.9	0.6
1.0	0.0
EOF

    cat << 'EOF' > /home/user/run2_gc.tsv
GC_Fraction	Density
0.0	0.0
0.1	0.2
0.2	0.8
0.3	1.4
0.4	1.8
0.5	1.6
0.6	1.2
0.7	1.0
0.8	1.2
0.9	0.8
1.0	0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
