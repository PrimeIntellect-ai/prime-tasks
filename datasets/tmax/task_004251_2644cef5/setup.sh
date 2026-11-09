#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/data/dataset.csv
text,label
"Hello, World! This is a test.",1
"Machine Learning is GREAT!!",1
"Bad data, terrible... sad.",0
"Another test line.",0
"Let's go!",1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
