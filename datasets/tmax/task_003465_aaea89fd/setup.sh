#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect git socat netcat-openbsd gcc binutils
    pip3 install pytest

    # Create the legacy binary
    mkdir -p /app/bin
    cat << 'EOF' > /tmp/calc_cost.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char region[256];
    int instances;

    printf("Welcome to FinOps Calculator V2.\n");
    printf("Enter Region (us-east, eu-west): ");
    fflush(stdout);
    if (scanf("%255s", region) != 1) return 1;

    printf("Enter Number of Instances: ");
    fflush(stdout);
    if (scanf("%d", &instances) != 1) return 1;

    int multiplier = 10;
    if (strcmp(region, "us-east") == 0) {
        multiplier = 10;
    } else if (strcmp(region, "eu-west") == 0) {
        multiplier = 20;
    }

    int cost = multiplier * instances;
    printf("Total Estimated Cost: $%d\n", cost);

    return 0;
}
EOF
    gcc /tmp/calc_cost.c -o /app/bin/calc_cost
    strip /app/bin/calc_cost
    rm /tmp/calc_cost.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
