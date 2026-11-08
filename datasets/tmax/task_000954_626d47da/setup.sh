#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/libcsv-graph
    mkdir -p /opt/oracle

    # Create the correct oracle
    cat << 'EOF' > /opt/oracle/in_degree_oracle.c
#include <stdio.h>
#include <stdlib.h>

#define MAX_NODES 100000

typedef struct {
    int node_id;
    int in_degree;
} Node;

int compare_nodes(const void *a, const void *b) {
    Node *nodeA = (Node *)a;
    Node *nodeB = (Node *)b;
    if (nodeB->in_degree != nodeA->in_degree) {
        return nodeB->in_degree - nodeA->in_degree; // descending
    }
    return nodeA->node_id - nodeB->node_id; // ascending
}

int main(int argc, char *argv[]) {
    if (argc != 5) return 1;
    char *input_csv = argv[1];
    int min_weight = atoi(argv[2]);
    int limit = atoi(argv[3]);
    int offset = atoi(argv[4]);

    FILE *fp = fopen(input_csv, "r");
    if (!fp) return 1;

    static int degrees[MAX_NODES] = {0};
    static int seen[MAX_NODES] = {0};

    int src, tgt, w;
    while (fscanf(fp, "%d,%d,%d", &src, &tgt, &w) == 3) {
        if (tgt >= 0 && tgt < MAX_NODES) {
            degrees[tgt] += w;
            seen[tgt] = 1;
        }
    }
    fclose(fp);

    Node nodes[MAX_NODES];
    int count = 0;
    for (int i = 0; i < MAX_NODES; i++) {
        if (seen[i] && degrees[i] >= min_weight) {
            nodes[count].node_id = i;
            nodes[count].in_degree = degrees[i];
            count++;
        }
    }

    qsort(nodes, count, sizeof(Node), compare_nodes);

    for (int i = offset; i < offset + limit && i < count; i++) {
        printf("Node: %d, In-Degree: %d\n", nodes[i].node_id, nodes[i].in_degree);
    }

    return 0;
}
EOF
    gcc -o /opt/oracle/in_degree_oracle /opt/oracle/in_degree_oracle.c

    # Create the buggy source code
    cat << 'EOF' > /app/libcsv-graph/in_degree.c
#include <stdio.h>
#include <stdlib.h>

#define MAX_NODES 100000

typedef struct {
    int node_id;
    int in_degree;
} Node;

int compare_nodes(const void *a, const void *b) {
    Node *nodeA = (Node *)a;
    Node *nodeB = (Node *)b;
    if (nodeB->in_degree != nodeA->in_degree) {
        return nodeA->in_degree - nodeB->in_degree; // Bug: ascending
    }
    return nodeB->node_id - nodeA->node_id; // Bug: descending
}

int main(int argc, char *argv[]) {
    if (argc != 5) return 1;
    char *input_csv = argv[1];
    int min_weight = atoi(argv[2]);
    int limit = atoi(argv[3]);
    int offset = atoi(argv[4]);

    FILE *fp = fopen(input_csv, "r");
    if (!fp) return 1;

    static int degrees[MAX_NODES] = {0};
    static int seen[MAX_NODES] = {0};

    int src, tgt, w;
    while (fscanf(fp, "%d,%d,%d", &src, &tgt, &w) == 3) {
        if (tgt >= 0 && tgt < MAX_NODES) {
            degrees[tgt] += w;
            seen[tgt] = 1;
        }
    }
    fclose(fp);

    Node nodes[MAX_NODES];
    int count = 0;
    for (int i = 0; i < MAX_NODES; i++) {
        if (seen[i] && degrees[i] < min_weight) { // Bug: < instead of >=
            nodes[count].node_id = i;
            nodes[count].in_degree = degrees[i];
            count++;
        }
    }

    qsort(nodes, count, sizeof(Node), compare_nodes);

    for (int i = offset; i < offset + limit && i < count; i++) {
        printf("Node: %d, In-Degree: %d\n", nodes[i].node_id, nodes[i].in_degree);
    }

    return 0;
}
EOF

    # Create the buggy Makefile
    cat << 'EOF' > /app/libcsv-graph/Makefile
all:
	gcc -c in_degree.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/libcsv-graph
