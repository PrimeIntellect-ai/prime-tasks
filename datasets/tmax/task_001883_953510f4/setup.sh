#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/graph.txt
A -> B
A -> C
B -> D
C -> D
D -> E
EOF

cat << 'EOF' > /home/user/graph_solver.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int adj[26][26] = {0};
int present[26] = {0};
int in_degree[26] = {0};

int* solve_graph() {
    // BUG: Returning a pointer to a local array causes undefined behavior.
    // Agent must fix this (e.g., using malloc or static).
    int sorted_nodes[26];
    int idx = 0;

    int queue[26];
    int head = 0, tail = 0;

    for (int i = 0; i < 26; i++) {
        if (present[i] && in_degree[i] == 0) {
            queue[tail++] = i;
        }
    }

    while (head < tail) {
        int u = queue[head++];
        sorted_nodes[idx++] = u;

        for (int v = 0; v < 26; v++) {
            if (adj[u][v]) {
                in_degree[v]--;
                if (in_degree[v] == 0) {
                    queue[tail++] = v;
                }
            }
        }
    }

    // Mark the end
    sorted_nodes[idx] = -1;
    return sorted_nodes;
}

int main() {
    char line[256];
    // State machine to parse "X -> Y"
    while (fgets(line, sizeof(line), stdin)) {
        char u_char, v_char;
        if (sscanf(line, "%c -> %c", &u_char, &v_char) == 2) {
            int u = u_char - 'A';
            int v = v_char - 'A';
            if (!adj[u][v]) {
                adj[u][v] = 1;
                present[u] = 1;
                present[v] = 1;
                in_degree[v]++;
            }
        }
    }

    int* result = solve_graph();

    for (int i = 0; i < 26; i++) {
        if (result[i] == -1) break;
        printf("%c\n", result[i] + 'A');
    }

    return 0;
}
EOF

cat << 'EOF' > /home/user/pipeline.py
import subprocess
import sys

def process_graph(file_path):
    # Python 2 syntax and bytes/str issues
    with open(file_path, 'r') as f:
        graph_data = f.read()

    p = subprocess.Popen(['/home/user/graph_solver'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    out, err = p.communicate(input=graph_data) # In py3, input must be bytes

    # In python 2, 'out' was a string. In py3 it's bytes.
    lines = out.split('\n')

    for line in lines:
        if line.strip():
            print line # Python 2 print statement

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print "Usage: pipeline.py <graph_file>"
        sys.exit(1)
    process_graph(sys.argv[1])
EOF

cat << 'EOF' > /home/user/build.sh
#!/bin/bash
gcc -O2 -Wall /home/user/graph_solver.c -o /home/user/graph_solver
EOF
chmod +x /home/user/build.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
