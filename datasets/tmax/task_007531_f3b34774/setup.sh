#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/pinns_data
    cat << 'EOF' > /home/user/pinns_data/baseline.txt
0.100000
0.553397
0.870916
1.100000
1.279509
1.428268
1.493288
1.553397
1.609312
1.661552
1.710534
1.756589
1.799981
1.840941
1.879667
1.916330
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
