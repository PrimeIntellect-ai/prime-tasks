#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    for i in $(seq 1 200); do echo $i >> /app/entities.csv; done

    cat << 'EOF' > /tmp/gen_binary.py
import random

nodes = list(range(1, 201))
edges = {n: [] for n in nodes}
random.seed(42)

for n in nodes:
    num_edges = random.randint(0, 5)
    edges[n] = random.sample(nodes, num_edges)

with open('/tmp/legacy.c', 'w') as f:
    f.write("#include <stdio.h>\n")
    f.write("#include <stdlib.h>\n")
    f.write("int main(int argc, char** argv) {\n")
    f.write("  if (argc < 2) return 1;\n")
    f.write("  int id = atoi(argv[1]);\n")
    f.write("  switch(id) {\n")
    for n in nodes:
        f.write(f"    case {n}: ")
        if edges[n]:
            f.write(f'printf("ACCESS:')
            for e in edges[n]:
                f.write(f' {e}')
            f.write('\\n"); break;\n')
        else:
            f.write('printf("ACCESS: NONE\\n"); break;\n')
    f.write("    default: printf(\"ACCESS: NONE\\n\"); break;\n")
    f.write("  }\n")
    f.write("  return 0;\n")
    f.write("}\n")
EOF
    python3 /tmp/gen_binary.py
    gcc -O3 -s /tmp/legacy.c -o /app/legacy_audit_tool
    chmod +x /app/legacy_audit_tool
    rm /tmp/legacy.c /tmp/gen_binary.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
