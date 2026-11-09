#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make jq
    pip3 install pytest

    mkdir -p /home/user/router_project

    cat << 'EOF' > /home/user/router_project/Makefile
url_router: router.c
    gcc -o url_router router.c # Uses spaces instead of tabs!
EOF

    cat << 'EOF' > /home/user/router_project/router.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("VALID:0\n");
        return 1;
    }

    char url[256];
    strncpy(url, argv[1], 255);
    url[255] = '\0';

    char *path = strtok(url, "?");
    char *query = strtok(NULL, "");

    // BUG: Missing NULL check for query before printing or processing
    if (strlen(query) > 0) {
        printf("ROUTE:%s|PARAMS:%s|VALID:1\n", path, query);
    } else {
        printf("ROUTE:%s|PARAMS:none|VALID:1\n", path);
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/router_project/urls.txt
/api/v1/users?id=10&active=true
/api/v1/status
/home?user=admin
/about
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
