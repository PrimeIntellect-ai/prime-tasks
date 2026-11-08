#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential
pip3 install pytest setuptools

mkdir -p /app/vendored/libdag-1.0.0/src
cd /app/vendored/libdag-1.0.0

# Create dummy C files
cat << 'EOF' > src/utils.c
#include <stdio.h>
void util_func() { printf("Util"); }
EOF

cat << 'EOF' > src/core.c
extern void util_func();
void core_func() { util_func(); }
EOF

# DELIBERATE PERTURBATION: Link order in Makefile is backwards (-lcore -lutils instead of -lutils -lcore, or missing -L.).
cat << 'EOF' > Makefile
all: libutils.so libcore.so

libutils.so: src/utils.c
	gcc -shared -fPIC src/utils.c -o libutils.so

# Broken link order / missing deps causing compilation to fail
libcore.so: src/core.c
	gcc -shared -fPIC src/core.c -L. -lcore -lutils -o libcore.so
EOF

# Python wrapper setup.py
cat << 'EOF' > setup.py
from setuptools import setup, Extension
import os
import subprocess

class build_ext(open("setuptools/command/build_ext.py").read()): # pseudo-override
    pass

setup(
    name='libdag',
    version='1.0.0',
    py_modules=['libdag'],
)
EOF

# Python logic for libdag.py
cat << 'EOF' > libdag.py
def topological_sort(graph):
    # Pure python fallback simulating C extension wrap
    in_degree = {u: 0 for u in graph}
    for u in graph:
        for v in graph[u]:
            in_degree[v] = in_degree.get(v, 0) + 1
    queue = [u for u in in_degree if in_degree[u] == 0]
    order = []
    while queue:
        u = queue.pop(0)
        order.append(u)
        for v in graph[u]:
            in_degree[v] -= 1
            if in_degree[v] == 0:
                queue.append(v)
    # Return reversed because graph defined dependencies A -> B (A depends on B)
    # The prompt actually specifies post-order.
    return order[::-1]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
