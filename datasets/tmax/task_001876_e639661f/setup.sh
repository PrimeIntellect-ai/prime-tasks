#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/ratelimit.cpp
#include <stdint.h>

// Bug: missing extern "C" causing C++ name mangling, breaking Python ctypes expectations.
int allow_request(uint32_t client_id, uint32_t max_reqs) {
    static uint32_t counts[1000] = {0};
    if (client_id >= 1000) return 0;
    counts[client_id]++;
    return counts[client_id] <= max_reqs ? 1 : 0;
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
all: libratelimit.so

libratelimit.so: ratelimit.o
	g++ -shared -o libratelimit.so ratelimit.o

ratelimit.o: ratelimit.cpp
	g++ -c -fPIC ratelimit.cpp -o ratelimit.o
EOF

    cat << 'EOF' > /home/user/requests.txt
12:GET /api/v1/users
INVALID_LINE
12:POST /api/v1/data
45:GET /status
12:DELETE /api/v1/users/1
malformed:request
45:POST /login
45:GET /dashboard
12:GET /retry
EOF

    cat << 'EOF' > /tmp/expected_api_results.log
ACCEPTED: 12:GET /api/v1/users
ACCEPTED: 12:POST /api/v1/data
ACCEPTED: 45:GET /status
REJECTED: 12:DELETE /api/v1/users/1
ACCEPTED: 45:POST /login
REJECTED: 45:GET /dashboard
REJECTED: 12:GET /retry
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
