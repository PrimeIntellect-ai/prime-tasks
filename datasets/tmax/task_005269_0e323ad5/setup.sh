#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libhiredis-dev redis-server curl
    pip3 install pytest

    mkdir -p /home/user/proxy_project
    mkdir -p /app

    # Create proxy.c with intentional bugs
    cat << 'EOF' > /home/user/proxy_project/proxy.c
#include <stdio.h>
#include <stdlib.h>
#include <hiredis/hiredis.h>
/* Missing string.h */

void resolve_cache_key(int depth) {
    /* Infinite recursion bug missing depth check */
    resolve_cache_key(depth + 1);
}

void parse_query_boundary(char *query, int len) {
    /* Off-by-one error */
    for (int i = 0; i <= len; i++) {
        query[i] = 'a';
    }
}

void read_chunked_data() {
    int chunk_size = 10;
    /* Missing chunk_size decrement */
    while (chunk_size > 0) {
        printf("Reading...\n");
    }
}

int main(int argc, char **argv) {
    printf("Starting proxy...\n");
    return 0;
}
EOF

    # Create correct proxy.c for oracle
    cat << 'EOF' > /app/oracle_proxy.c
#include <stdio.h>
int main() {
    return 0;
}
EOF
    gcc /app/oracle_proxy.c -o /app/oracle_proxy
    rm /app/oracle_proxy.c

    # Create Makefile with missing -lhiredis
    cat << 'EOF' > /home/user/proxy_project/Makefile
proxy: proxy.c
	gcc -o proxy proxy.c
EOF

    # Create start_services.sh
    cat << 'EOF' > /home/user/proxy_project/start_services.sh
#!/bin/bash
echo "Starting services..."
EOF
    chmod +x /home/user/proxy_project/start_services.sh

    # Create config.env
    cat << 'EOF' > /home/user/proxy_project/config.env
PROXY_PORT=
BACKEND_URL=
REDIS_HOST=
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
