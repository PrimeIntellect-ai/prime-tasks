#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev binutils
    pip3 install pytest

    mkdir -p /home/user/src /home/user/data /app

    cat << 'EOF' > /home/user/src/train_model.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Flawed linear regression with data leak
int main() {
    printf("OOB MSE: 1.5000\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data/dataset.csv
f1,f2,f3,f4,f5,target
1.0,2.0,3.0,4.0,5.0,15.0
2.0,3.0,4.0,5.0,6.0,20.0
EOF

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
int main() {
    printf("OOB MSE: 2.4512\n");
    return 0;
}
EOF
    gcc -o /app/oracle_pipeline /tmp/oracle.c
    strip /app/oracle_pipeline
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
