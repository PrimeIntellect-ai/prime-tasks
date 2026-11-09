#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make netcat-openbsd socat curl jq gawk
    pip3 install pytest

    mkdir -p /app/vendored/deptool

    cat << 'EOF' > /app/vendored/deptool/main.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "src/App.java") == 0) {
        printf("//app:main\n");
    } else {
        printf("//app:other\n");
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/vendored/deptool/Makefile
all:
ifndef BUILD_ENV
	$(error BUILD_ENV is not set)
endif
ifneq ($(BUILD_ENV),mobile)
	$(error BUILD_ENV must be mobile)
endif
	gcc -o deptool main.c -lbadlib
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
