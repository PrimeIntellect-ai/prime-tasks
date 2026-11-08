#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/api_project

    cat << 'EOF' > /home/user/api_project/router.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        return 1;
    }

    char *url = argv[1];
    if (url[0] != '/') {
        return 1; // Invalid route
    }

    char route[256] = {0};
    char params[256] = {0};

    char *question_mark = strchr(url, '?');
    if (question_mark != NULL) {
        strncpy(route, url, question_mark - url);
        strcpy(params, question_mark + 1);
    } else {
        strcpy(route, url);
        strcpy(params, "NONE");
    }

    printf("Route: %s\nParams: %s\n", route, params);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/api_project/Makefile
router: router.c
	gcc -Wall -O2 -o router
EOF

    cat << 'EOF' > /home/user/api_project/urls.txt
/api/v1/health
/api/v2/users?active=true&sort=desc
malformed/url/path
/webhooks/stripe?sig=xyz123
admin/dashboard
/
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/api_project
    chmod -R 777 /home/user
