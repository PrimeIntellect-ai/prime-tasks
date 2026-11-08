#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc valgrind jq nginx
pip3 install pytest

mkdir -p /home/user/math_lib /home/user/ci

cat << 'EOF' > /home/user/math_lib/matrix_trace.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int n;
    if (scanf("%d", &n) != 1) return 1;

    // Allocate memory for n x n matrix
    int **matrix = (int **)malloc(n * sizeof(int *));
    for (int i = 0; i < n; i++) {
        matrix[i] = (int *)malloc(n * sizeof(int));
    }

    // Read matrix elements
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            scanf("%d", &matrix[i][j]);
        }
    }

    // Calculate trace with intentional off-by-one error (i <= n instead of i < n)
    int trace = 0;
    for (int i = 0; i <= n; i++) {
        trace += matrix[i][i];
    }

    printf("%d\n", trace);

    // Intentional memory leak: missing free() calls
    return 0;
}
EOF

cp /home/user/math_lib/matrix_trace.c /home/user/math_lib/matrix_trace.c.orig

cat << 'EOF' > /home/user/ci/test_vectors.json
[
  {
    "id": "test_1",
    "size": 3,
    "matrix": [1, 2, 3, 4, 5, 6, 7, 8, 9]
  },
  {
    "id": "test_2",
    "size": 2,
    "matrix": [10, -5, 3, 20]
  },
  {
    "id": "test_3",
    "size": 4,
    "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
  }
]
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/math_lib /home/user/ci
chmod -R 777 /home/user
