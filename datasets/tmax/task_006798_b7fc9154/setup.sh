#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/target.txt
70.76742517865234
50.08028799446344
35.44053911666993
25.080516480838116
17.748833959145607
12.560416413251412
8.888686616056345
6.290906295324083
4.451915470557245
3.1505395758371353
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
