#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make time jq
    pip3 install pytest

    mkdir -p /home/user/src

    # Create filter.c
    cat << 'EOF' > /home/user/src/filter.c
#include <string.h>

int is_valid_ip(const char* ip) {
    // Simple mock validation: invalid if it starts with 999
    if (strncmp(ip, "999.", 4) == 0) {
        return 0;
    }
    return 1;
}
EOF

    # Create route.conf
    cat << 'EOF' > /home/user/route.conf
<route /api/login>
method POST
limit 2
</route>
<route /api/data>
method GET
limit 4
</route>
EOF

    # Create requests.log
    cat << 'EOF' > /home/user/requests.log
192.168.1.100 1000 /api/login
192.168.1.100 1010 /api/login
192.168.1.100 1050 /api/login
10.0.0.5 1000 /api/data
10.0.0.5 1010 /api/data
10.0.0.5 1020 /api/data
10.0.0.5 1030 /api/data
10.0.0.5 1040 /api/data
999.999.999.999 1000 /api/login
999.999.999.999 1010 /api/login
999.999.999.999 1020 /api/login
172.16.0.2 2000 /api/login
172.16.0.2 2100 /api/login
172.16.0.2 2110 /api/login
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
