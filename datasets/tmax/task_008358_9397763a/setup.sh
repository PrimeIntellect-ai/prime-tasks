#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk sed grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/train.tsv
1	Hello world, this is a test.
2	Another test! Hello again.
invalid line here
3	World of bash scripting.
EOF

    cat << 'EOF' > /home/user/test.tsv
1	Hello world!
2	This is a new test.
not an integer	Bad schema
3	Bash is great, hello world.
EOF

    chmod -R 777 /home/user
