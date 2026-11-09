#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential libc6-dev
    pip3 install pytest

    mkdir -p /home/user/artifacts
    cd /home/user/artifacts

    # Create tree
    cat << 'EOF' > tree.c
#include <stdint.h>
uint32_t process_chunk(uint32_t state) {
    return state ^ 0xAAAA;
}
EOF
    echo -n "" > tree.deps

    # Create node
    cat << 'EOF' > node.c
#include <stdint.h>
uint32_t process_chunk(uint32_t state) {
    return state + 0x01020304;
}
EOF
    echo "tree" > node.deps

    # Create graph
    cat << 'EOF' > graph.c
#include <stdint.h>
uint32_t process_chunk(uint32_t state) {
    return state * 5;
}
EOF
    echo "node" > graph.deps

    # Create edge
    cat << 'EOF' > edge.c
#include <stdint.h>
uint32_t process_chunk(uint32_t state) {
    return (state << 4) | (state >> 28);
}
EOF
    echo "graph" > edge.deps

    # Create vertex
    cat << 'EOF' > vertex.c
#include <stdint.h>
uint32_t process_chunk(uint32_t state) {
    return state ^ 0xFFFFFFFF;
}
EOF
    echo "edge" > vertex.deps

    # Compile shared libraries
    gcc -shared -fPIC tree.c -o libtree.so
    gcc -shared -fPIC node.c -o libnode.so
    gcc -shared -fPIC graph.c -o libgraph.so
    gcc -shared -fPIC edge.c -o libedge.so
    gcc -shared -fPIC vertex.c -o libvertex.so

    rm *.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
