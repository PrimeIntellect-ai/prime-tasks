#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/src /home/user/raw_billing

    # Create mock billing data
    echo "instance_id,cost,status" > /home/user/raw_billing/data.csv
    echo "i-1234567890abcdef0,12.50,running" >> /home/user/raw_billing/data.csv
    echo "i-0987654321fedcba0,45.00,stopped" >> /home/user/raw_billing/data.csv

    # Create buggy C program
    cat << 'EOF' > /home/user/src/analyzer.c
#include <stdio.h>
// Missing standard library header for getenv

int main() {
    char *region = getnv("CLOUD_REGION"); // Typo: getnv instead of getenv
    if (region == NULL) {
        printf("Error: CLOUD_REGION not set\n");
        return 1;
    }
    printf("Cost analysis for region: %s\n", region);
    printf("Idle resources found: 1\n");
    printf("Potential savings: $45.00\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
