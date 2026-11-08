#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk bc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_spectra.txt
100 1.0
101 2.0
102 12.0
103 18.0
104 10.0
105 2.0
106 1.0
107 4.0
108 14.0
109 20.0
110 15.0
111 6.0
112 1.0
113 0.5
114 0.1
EOF
    chmod 644 /home/user/raw_spectra.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
