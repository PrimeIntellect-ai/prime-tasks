#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake gcc make
    pip3 install pytest

    mkdir -p /home/user/data_migration/c_src/build
    mkdir -p /home/user/data_migration/nodes

    cat << 'EOF' > /home/user/data_migration/c_src/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(DataMigration)

add_library(mathops SHARED mathops.c)
add_executable(calc_node calc_node.c)
# BUG: Missing link libraries
# target_link_libraries(calc_node mathops)
EOF

    cat << 'EOF' > /home/user/data_migration/c_src/mathops.c
#include "mathops.h"
int transform(int value) {
    return (value ^ 0x5A) + 12;
}
EOF

    cat << 'EOF' > /home/user/data_migration/c_src/mathops.h
#ifndef MATHOPS_H
#define MATHOPS_H
int transform(int value);
#endif
EOF

    cat << 'EOF' > /home/user/data_migration/c_src/calc_node.c
#include <stdio.h>
#include <stdlib.h>
#include "mathops.h"

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    int val = atoi(argv[1]);
    printf("%d\n", transform(val));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data_migration/dag_parser.py
import sys
import os

def parse_node(filepath):
    deps = []
    value = 0
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('DEPS:'):
                d_str = line[5:].strip()
                if d_str:
                    deps = [x.strip() for x in d_str.split(',')]
            elif line.startswith('VALUE:'):
                value = int(line[6:].strip())

    # Python 2 specific syntaxes to force migration
    print "VALUE:", value
    if len(deps) > 0:
        print "DEPS:", ",".join(deps)
    else:
        print "DEPS: NONE"

    # Useless xrange to force Python 3 fix
    total = 0
    for i in xrange(value):
        total += 1

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print "Usage: dag_parser.py <file>"
        sys.exit(1)
    parse_node(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/data_migration/nodes/root.node
DEPS: child1.node, child2.node
VALUE: 100
EOF

    cat << 'EOF' > /home/user/data_migration/nodes/child1.node
DEPS: leaf1.node
VALUE: 50
EOF

    cat << 'EOF' > /home/user/data_migration/nodes/child2.node
DEPS: leaf1.node, leaf2.node
VALUE: 75
EOF

    cat << 'EOF' > /home/user/data_migration/nodes/leaf1.node
DEPS: 
VALUE: 10
EOF

    cat << 'EOF' > /home/user/data_migration/nodes/leaf2.node
DEPS: 
VALUE: 20
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
