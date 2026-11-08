#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app
mkdir -p /home/user

cat << 'EOF' > /tmp/legacy_lb_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char ip[20];
    int port;
    int weight;
} Backend;

int compare(const void *a, const void *b) {
    Backend *ba = (Backend *)a;
    Backend *bb = (Backend *)b;
    if (ba->weight != bb->weight) return ba->weight - bb->weight;
    int len_a = strlen(ba->ip);
    int len_b = strlen(bb->ip);
    if (len_a != len_b) return len_a - len_b;
    int cmp = strcmp(ba->ip, bb->ip);
    if (cmp != 0) return cmp;
    return ba->port - bb->port;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *input = strdup(argv[1]);
    Backend backends[1000];
    int count = 0;

    char *token = strtok(input, ",");
    while (token != NULL) {
        sscanf(token, "%19[^:]:%d:%d", backends[count].ip, &backends[count].port, &backends[count].weight);
        count++;
        token = strtok(NULL, ",");
    }

    qsort(backends, count, sizeof(Backend), compare);

    printf("# Load Balancer Configuration\n");
    printf("# Generated for %d backends\n", count);
    printf("upstream cluster {\n");
    for (int i = 0; i < count; i++) {
        printf("    server %s:%d weight=%d maxconn=%d;\n", backends[i].ip, backends[i].port, backends[i].weight % 5, backends[i].weight * 10);
    }
    printf("}\n");

    free(input);
    return 0;
}
EOF

gcc -O2 -o /app/legacy_lb_gen /tmp/legacy_lb_gen.c
strip /app/legacy_lb_gen
rm /tmp/legacy_lb_gen.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
