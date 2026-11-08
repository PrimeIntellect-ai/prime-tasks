#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils netcat-openbsd socat
    pip3 install pytest scikit-learn pandas numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/embedder.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        unsigned int seed = 0;
        for(int i=0; buffer[i] != '\0' && buffer[i] != '\n'; i++) {
            seed = seed * 31 + buffer[i];
        }
        srand(seed);
        for(int i=0; i<64; i++) {
            printf("%f%s", (float)rand() / RAND_MAX, i==63 ? "" : ",");
        }
        printf("\n");
    }
    return 0;
}
EOF

    gcc -O2 /tmp/embedder.c -o /app/query_embedder
    strip /app/query_embedder
    rm /tmp/embedder.c

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
id,text
1,The quick brown fox
2,Jumps over the lazy dog
3,Data science is fun
4,Embeddings represent semantic meaning
5,Dimensionality reduction helps visualization
EOF

    chmod -R 777 /home/user
