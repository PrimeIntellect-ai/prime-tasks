#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/src
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/raw_logs.tsv
1670000000	S1	48656c6c6f20576f726c6421
1670000060	S2	4572726f723a204f76657268656174313233
1670000120	S1	4f4b
1670000180	S3	3132333435
1670000240	S1	5761726e696e672d4c6f772d426174746572792e
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
