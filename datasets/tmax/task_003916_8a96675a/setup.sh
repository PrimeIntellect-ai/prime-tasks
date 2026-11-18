#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/mathlib/lib

cat << 'EOF' > /home/user/mathlib/matrix.c
void matrix_mult(int size, int* a, int* b, int* out) {
    for (int i = 0; i < size; i++) {
        for (int j = 0; j < size; j++) {
            out[i * size + j] = 0;
            for (int k = 0; k < size; k++) {
                out[i * size + j] += a[i * size + k] * b[k * size + j];
            }
        }
    }
}
void matrix_copy(int size, int* src, int* dst) {
    for (int i = 0; i < size * size; i++) dst[i] = src[i];
}
EOF

cat << 'EOF' > /home/user/mathlib/graph.c
#include <stdlib.h>
extern void matrix_mult(int size, int* a, int* b, int* out);
extern void matrix_copy(int size, int* src, int* dst);

int count_paths(int* adj_matrix, int size, int steps, int start_node, int end_node) {
    if (steps == 0) return start_node == end_node ? 1 : 0;

    int* current = (int*)malloc(size * size * sizeof(int));
    int* next = (int*)malloc(size * size * sizeof(int));

    // Identity matrix initially if we were doing power, but since steps >= 1:
    matrix_copy(size, adj_matrix, current);

    for (int s = 1; s < steps; s++) {
        matrix_mult(size, current, adj_matrix, next);
        matrix_copy(size, next, current);
    }

    int result = current[start_node * size + end_node];
    free(current);
    free(next);
    return result;
}
EOF

cat << 'EOF' > /home/user/mathlib/build.sh
#!/bin/bash
mkdir -p lib
gcc -shared -fPIC matrix.c -o lib/libmatrix.so
gcc -shared -fPIC graph.c -L./lib -lmatrix -o lib/libgraph.so
EOF
chmod +x /home/user/mathlib/build.sh

cat << 'EOF' > /home/user/mathlib/graph_wrapper.py
import ctypes
import os

lib_path = os.path.join(os.path.dirname(__file__), 'lib', 'libgraph.so')
_graph = ctypes.CDLL(lib_path)

_count_paths = _graph.count_paths
_count_paths.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]
_count_paths.restype = ctypes.c_int

def get_path_count(adj_matrix: list[list[int]], steps: int, start: int, end: int) -> int:
    size = len(adj_matrix)
    flat = [item for sublist in adj_matrix for item in sublist]
    c_array = (ctypes.c_int * len(flat))(*flat)
    return _count_paths(c_array, size, steps, start, end)
EOF

cd /home/user/mathlib && ./build.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
