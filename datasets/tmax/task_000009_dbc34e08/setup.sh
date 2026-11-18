#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/rna_data.txt
>Time_0.0
read_count:100.0
>Time_0.5
read_count:10.2
>Time_1.0
read_count:2.7
>Time_1.5
read_count:2.1
>Time_2.0
read_count:2.0
EOF

    chmod -R 777 /home/user
