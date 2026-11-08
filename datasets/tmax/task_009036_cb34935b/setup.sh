#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/router

    cat << 'EOF' > /home/user/router/deeplink_router.h
#ifndef DEEPLINK_ROUTER_H
#define DEEPLINK_ROUTER_H

typedef struct {
    char scheme[32];
    char route[64];
    char param_key[32];
    char param_value[64];
} ParsedUrl;

int parse_url(const char* url, ParsedUrl* out);

#endif
EOF

    cat << 'EOF' > /home/user/router/deeplink_router.c
#include <stdio.h>
#include <string.h>
#include "deeplink_router.h"

int parse_url(const char* url, ParsedUrl* out) {
    int state = 0; // 0: scheme, 1: route, 2: param_key, 3: param_value
    int i = 0, j = 0;
    out->scheme[0] = out->route[0] = out->param_key[0] = out->param_value[0] = '\0';

    char* current_buf = out->scheme;

    while(url[i] != '\0') {
        if (state == 0 && strncmp(&url[i], "://", 3) == 0) {
            current_buf[j] = '\0';
            state = 1;
            i += 3;
            current_buf = out->route;
            j = 0;
            continue;
        } else if (state == 1 && url[i] == '?') {
            current_buf[j] = '\0';
            state = 2;
            // BUG: skips '?' and the first character of the param key
            i += 2; 
            current_buf = out->param_key;
            j = 0;
            continue;
        } else if (state == 2 && url[i] == '=') {
            current_buf[j] = '\0';
            state = 3;
            i++;
            current_buf = out->param_value;
            j = 0;
            continue;
        }
        current_buf[j++] = url[i++];
    }
    current_buf[j] = '\0';
    return 1;
}
EOF

    cat << 'EOF' > /home/user/router/main.c
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "deeplink_router.h"

int main(int argc, char** argv) {
    if (argc < 2) return 1;

    // Artificial math dependency
    double x = sin(0.5);

    if (strcmp(argv[1], "test") == 0) {
        ParsedUrl p;
        parse_url("app://profile?id=123", &p);
        if (strcmp(p.scheme, "app") == 0 &&
            strcmp(p.route, "profile") == 0 &&
            strcmp(p.param_key, "id") == 0 &&
            strcmp(p.param_value, "123") == 0) {
            printf("ALL TESTS PASSED\n");
            return 0;
        } else {
            printf("TEST FAILED: scheme='%s', route='%s', param_key='%s', param_value='%s'\n",
                   p.scheme, p.route, p.param_key, p.param_value);
            return 1;
        }
    } else if (strcmp(argv[1], "bench") == 0) {
        ParsedUrl p;
        for (int i=0; i<100000; i++) {
            parse_url("app://profile?id=123", &p);
        }
        printf("Parsed 100000 URLs\n");
        return 0;
    }
    return 1;
}
EOF

    cat << 'EOF' > /home/user/router/Makefile
CC=gcc
CFLAGS=-O2

all: router

router: main.o deeplink_router.o
	$(CC) $(CFLAGS) -lm main.o deeplink_router.o -o router

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

deeplink_router.o: deeplink_router.c
	$(CC) $(CFLAGS) -c deeplink_router.c

clean:
	rm -f *.o router
EOF

    cat << 'EOF' > /home/user/router/benchmark.sh
#!/bin/bash
time ./router bench
EOF

    chmod +x /home/user/router/benchmark.sh
    chown -R user:user /home/user/router
    chmod -R 777 /home/user
