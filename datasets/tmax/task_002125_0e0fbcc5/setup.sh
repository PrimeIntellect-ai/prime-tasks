#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb git
    pip3 install pytest

    mkdir -p /home/user/perf_app
    cd /home/user/perf_app
    git init

    cat << 'EOF' > compute.h
#ifndef COMPUTE_H
#define COMPUTE_H
void compute_metrics(const char* key);
#endif
EOF

    cat << 'EOF' > compute.c
#include "compute.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

void compute_metrics(const char* key) {
    const char* legacy_key = "pr0f1l3_x89_K";
    if (strcmp(key, legacy_key) != 0) {
        printf("Invalid key\n");
        exit(1);
    }

    int *results = malloc(10 * sizeof(int));
    for(int i=0; i<10; i++) {
        results[i] = (int)sqrt((double)(i * 100));
    }

    FILE *f = fopen("/home/user/profile_results.txt", "w");
    for(int i=0; i<10; i++) {
        fprintf(f, "Result %d: %d\n", i, results[i]);
    }
    fclose(f);
}
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include "compute.h"

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("Usage: %s <api_key>\n", argv[0]);
        return 1;
    }
    compute_metrics(argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
gcc -g -O0 main.c -o metrics_calc
EOF
    chmod +x build.sh

    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git add .
    git commit -m "Initial commit with working compute logic"

    cat << 'EOF' > compute.c
#include "compute.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

void compute_metrics(const char* key) {
    // API Key removed for security, now passed as argument
    if (strcmp(key, "pr0f1l3_x89_K") != 0) {
        printf("Invalid key\n");
        exit(1);
    }

    int *results = NULL; // BUG: memory no longer allocated
    for(int i=0; i<10; i++) {
        results[i] = (int)sqrt((double)(i * 100));
    }

    FILE *f = fopen("/home/user/profile_results.txt", "w");
    for(int i=0; i<10; i++) {
        fprintf(f, "Result %d: %d\n", i, results[i]);
    }
    fclose(f);
}
EOF

    git add compute.c
    git commit -m "Security: Removed hardcoded legacy API key and refactored"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
