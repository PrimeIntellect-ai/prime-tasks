#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/deps.txt
module_main module_ui module_auth
module_ui module_core
module_auth module_crypto
module_crypto module_core
module_core
EOF

    cat << 'EOF' > /home/user/pipeline/topo.py
import sys
from collections import defaultdict

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    graph = defaultdict(list)
    nodes = set()

    with open(sys.argv[1], 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            node = parts[0]
            nodes.add(node)
            for dep in parts[1:]:
                graph[node].append(dep)
                nodes.add(dep)

    visited = set()
    temp_mark = set()
    order = []

    def visit(n):
        if n in temp_mark:
            raise Exception("Cycle detected")
        if n not in visited:
            temp_mark.add(n)
            for m in graph[n]:
                visit(m)
            temp_mark.remove(n)
            visited.add(n)
            order.insert(0, n)

    for node in sorted(list(nodes)):
        if node not in visited:
            visit(node)

    print(" ".join(order))

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' | sed 's/^PREFIX//' > /home/user/pipeline/Makefile
PREFIXOBJS = $(addsuffix .o, $(shell ./topo.sh deps.txt))
PREFIX
PREFIXapp: $(OBJS)
PREFIX	gcc -o app $(OBJS)
PREFIX
PREFIX%.o: %.c
PREFIX	gcc -c $< -o $@
PREFIX
PREFIXtest: app
PREFIX	./app > test_results.log
PREFIX
PREFIXclean:
PREFIX	rm -f *.o app test_results.log
EOF

    cat << 'EOF' > /home/user/pipeline/module_core.c
int core_init() { return 10; }
EOF

    cat << 'EOF' > /home/user/pipeline/module_crypto.c
int core_init();
int crypto_init() { return core_init() + 5; }
EOF

    cat << 'EOF' > /home/user/pipeline/module_auth.c
int crypto_init();
int auth_init() { return crypto_init() + 2; }
EOF

    cat << 'EOF' > /home/user/pipeline/module_ui.c
int core_init();
int ui_init() { return core_init() + 8; }
EOF

    cat << 'EOF' > /home/user/pipeline/module_main.c
#include <stdio.h>
int ui_init();
int auth_init();

int main() {
    printf("INIT_SUCCESS: %d\n", ui_init() + auth_init());
    return 0;
}
EOF

    chmod +x /home/user/pipeline/topo.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
