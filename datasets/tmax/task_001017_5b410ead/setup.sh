#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make jq file
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/solver

    cat << 'EOF' > /home/user/solver/solver.c
#include <stdio.h>
#include <stdlib.h>

int subset_sum(int* arr, int n, int target) {
    // BUG: dp array allocated with size 'target', but accessed up to 'target' (needs target+1)
    // This causes memory corruption and segfaults on some targets
    int *dp = (int*)malloc(target * sizeof(int));

    // BUG: loop goes up to 'target', causing out of bounds write
    for(int i = 0; i <= target; i++) {
        dp[i] = 0;
    }
    dp[0] = 1;

    for(int i = 0; i < n; i++) {
        for(int j = target; j >= arr[i]; j--) {
            if(dp[j - arr[i]]) {
                dp[j] = 1;
            }
        }
    }

    int result = dp[target];
    free(dp); // This might crash if heap corruption occurred due to OOB write
    return result;
}
EOF

    cat << 'EOF' > /home/user/solver/Makefile
all:
	gcc -o libsolver.so solver.c
EOF

    chmod -R 777 /home/user
