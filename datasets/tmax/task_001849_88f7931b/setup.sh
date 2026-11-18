#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/schema_gen.c
#include <stdio.h>
int main() {
    // Base64 encoded representation of:
    // USER_ID|USER_NAME|CREATED_AT\n101|alice|2021-01-01\n102|bob|2022-02-02\n
    printf("VVNFUl9JRHxVU0VSX05BTUV8Q1JFQVRFRF9BVAoxMDF8YWxpY2V8MjAyMS0wMS0wMQoxMDJ8Ym9ifDIwMjItMDItMDIK\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
