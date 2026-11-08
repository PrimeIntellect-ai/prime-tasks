#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc upx-ucl sqlite3
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/detector.c
#include <stdio.h>
#include <stdlib.h>

#define MAX_EDGES 10000

int src[MAX_EDGES];
int dst[MAX_EDGES];

int main() {
    int u, v;
    int n = 0;
    while (scanf("%d %d", &u, &v) == 2) {
        if (n < MAX_EDGES) {
            src[n] = u;
            dst[n] = v;
            n++;
        }
    }

    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            if (dst[i] == src[j]) {
                for (int k = 0; k < n; k++) {
                    if (dst[j] == src[k] && dst[k] == src[i]) {
                        return 1;
                    }
                }
            }
        }
    }
    return 0;
}
EOF
    gcc -O3 -o /app/legacy_detector /app/detector.c
    strip /app/legacy_detector || true
    upx /app/legacy_detector || true

    mkdir -p /verify/corpus/evil
    mkdir -p /verify/corpus/clean

    cat << 'EOF' > /verify/corpus/evil/graph1.txt
1 2
2 3
3 1
4 5
EOF

    cat << 'EOF' > /verify/corpus/evil/graph2.txt
10 20
20 30
30 40
40 20
EOF

    cat << 'EOF' > /verify/corpus/clean/graph1.txt
1 2
2 3
3 4
4 5
EOF

    cat << 'EOF' > /verify/corpus/clean/graph2.txt
10 20
20 30
30 40
20 50
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
