#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Create the C library
    cat << 'EOF' > hasher.c
#include <stdint.h>

uint32_t compute_hash(const int32_t* data, int length) {
    uint32_t hash = 5381;
    for (int i = 0; i < length; i++) {
        hash = ((hash << 5) + hash) + (uint32_t)data[i];
    }
    return hash;
}
EOF

    gcc -shared -o libhasher.so -fPIC hasher.c

    # Create the upload logs
    cat << 'EOF' > upload_logs.txt
Some random log garbage
START_REQ
USER: alice
TS: 100
SIZE: 500
END_REQ
START_REQ
TS: 110
USER: bob
SIZE: 200
END_REQ
START_REQ
USER: alice
TS: 120
SIZE: 600
END_REQ
START_REQ
USER: alice
TS: 130
SIZE: 700
END_REQ
START_REQ
USER: alice
TS: 160
SIZE: 800
END_REQ
START_REQ
USER: bob
TS: 165
SIZE: 300
END_REQ
START_REQ
USER: bob
TS: 166
SIZE: 400
END_REQ
START_REQ
USER: bob
TS: 167
SIZE: 500
END_REQ
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
