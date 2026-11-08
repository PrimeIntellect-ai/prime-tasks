#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/semver-resolve

    cat << 'EOF' > /home/user/semver-resolve/resolve.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_VERSIONS 100
#define MAX_CONSTRAINTS 100

// BUG: Naive string comparison doesn't work for semver (e.g., "1.10.0" < "1.2.0")
int compare_versions(const char *v1, const char *v2) {
    return strcmp(v1, v2);
}

int check_constraint(const char *version, const char *op, const char *target) {
    int cmp = compare_versions(version, target);
    if (strcmp(op, "==") == 0) return cmp == 0;
    if (strcmp(op, "!=") == 0) return cmp != 0;
    if (strcmp(op, ">=") == 0) return cmp >= 0;
    if (strcmp(op, "<=") == 0) return cmp <= 0;
    if (strcmp(op, ">") == 0) return cmp > 0;
    if (strcmp(op, "<") == 0) return cmp < 0;
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <available.txt> <constraints.txt>\n", argv[0]);
        return 1;
    }

    FILE *f_avail = fopen(argv[1], "r");
    FILE *f_const = fopen(argv[2], "r");
    if (!f_avail || !f_const) {
        perror("Error opening files");
        return 1;
    }

    char available[MAX_VERSIONS][32];
    int avail_count = 0;
    while (fscanf(f_avail, "%31s", available[avail_count]) == 1) {
        avail_count++;
    }

    char ops[MAX_CONSTRAINTS][4];
    char targets[MAX_CONSTRAINTS][32];
    int const_count = 0;
    while (fscanf(f_const, "%3s %31s", ops[const_count], targets[const_count]) == 2) {
        const_count++;
    }

    char *best_version = NULL;

    for (int i = 0; i < avail_count; i++) {
        int valid = 1;
        for (int j = 0; j < const_count; j++) {
            if (!check_constraint(available[i], ops[j], targets[j])) {
                valid = 0;
                break;
            }
        }
        if (valid) {
            if (best_version == NULL || compare_versions(available[i], best_version) > 0) {
                best_version = available[i];
            }
        }
    }

    if (best_version) {
        printf("%s\n", best_version);
    } else {
        printf("None\n");
    }

    fclose(f_avail);
    fclose(f_const);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/semver-resolve/available.txt
0.9.5
1.0.0
1.1.9
1.2.0
1.10.2
1.11.0
2.0.0
2.0.1
EOF

    iconv -f UTF-8 -t UTF-16LE << 'EOF' > /home/user/semver-resolve/constraints.txt
>= 1.0.0
< 2.0.0
!= 1.2.0
!= 1.10.2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
