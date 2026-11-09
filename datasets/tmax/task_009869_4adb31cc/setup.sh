#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev jq binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > plugin.c
#include <stdio.h>
#include <math.h>

void initialize() {
    printf("Init\n");
}

double compute(double x) {
    return sin(x);
}
EOF

    gcc -shared -fPIC -o plugin.so plugin.c -lm
    rm plugin.c

    cat << 'EOF' > rules.json
{
  "max_glibc_version": "2.35",
  "required_exports": ["compute", "initialize", "cleanup"]
}
EOF

    chmod -R 777 /home/user
