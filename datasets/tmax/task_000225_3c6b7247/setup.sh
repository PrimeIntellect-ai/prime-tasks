#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_alignments.tsv
AlignmentID	TargetSeq	Score
A001	GATTACAGGG	1.25
A002	GATTACAT	0.55
A003	GATCCTAG	8.88
A004	GATTACA	9.99
A005	GATTACACCC	2.10
A006	GATTACAGGGAA	0.01
A007	GATTACAAG	4.44
A008	GATTACATTT	3.41
A009	GATTACAGGGAA	9.99
A010	GATTAC	5.55
A011	GATTACA	3.33
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
