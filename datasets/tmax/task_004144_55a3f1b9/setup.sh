#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ curl binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int n, m;
    if (scanf("%d %d", &n, &m) != 2) return 1;

    int** adj = (int**)calloc(n, sizeof(int*));
    for(int i=0; i<n; i++) adj[i] = (int*)calloc(n, sizeof(int));

    for(int i=0; i<m; i++) {
        int u, v;
        if (scanf("%d %d", &u, &v) == 2) {
            adj[u][v] = 1;
            adj[v][u] = 1;
        }
    }

    int triangles = 0;
    for(int i=0; i<n; i++) {
        for(int j=i+1; j<n; j++) {
            for(int k=j+1; k<n; k++) {
                if (adj[i][j] && adj[j][k] && adj[k][i]) {
                    triangles++;
                }
            }
        }
    }

    float score = (m * 1.5) + (triangles * 3.2);
    printf("%.2f\n", score);
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/mol_oracle
    strip /app/mol_oracle
    chmod +x /app/mol_oracle

    curl -sL https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h -o /app/httplib.h

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
