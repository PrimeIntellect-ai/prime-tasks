#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx numpy scipy matplotlib pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/viral_samples.csv
Timepoint,Sequence,Abundance
0,ACGTG,10.0
1,ACGTG,12.0
2,ACGTG,15.0
3,ACGTG,14.0
4,ACGTG,10.0
5,ACGTG,5.0
0,ACGTA,0.0
1,ACGTA,2.0
2,ACGTA,5.0
3,ACGTA,10.0
4,ACGTA,15.0
5,ACGTA,20.0
2,ACGCA,1.0
3,ACGCA,3.0
4,ACGCA,5.0
5,ACGCA,8.0
0,TGCAT,5.0
1,TGCAT,5.0
2,TGCAT,5.0
3,TGCAT,5.0
4,TGCAT,5.0
5,TGCAT,5.0
0,TGCAA,1.0
1,TGCAA,1.0
2,TGCAA,1.0
3,TGCAA,1.0
4,TGCAA,1.0
5,TGCAA,1.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
