#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
1,User,Alice
2,User,Bob
3,Post,Hello
4,Post,World
5,Product,Widget
6,Product,Gadget
7,User,Charlie
8,Post,News
EOF

    cat << 'EOF' > /home/user/edges.csv
1,3,CREATED
2,4,CREATED
3,5,MENTIONS
4,6,MENTIONS
1,4,LIKES
7,8,CREATED
8,5,MENTIONS
EOF

    cat << 'EOF' > /home/user/find_paths.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int id; char type[32]; char name[32]; } Node;
typedef struct { int source_id; int target_id; char relation_type[32]; } Edge;

Node nodes[100];
int num_nodes = 0;
Edge edges[100];
int num_edges = 0;

Node* get_node(int id) {
    for (int i = 0; i < num_nodes; i++) {
        if (nodes[i].id == id) return &nodes[i];
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    FILE *fn = fopen("/home/user/nodes.csv", "r");
    while (fscanf(fn, "%d,%[^,],%[^\n]", &nodes[num_nodes].id, nodes[num_nodes].type, nodes[num_nodes].name) == 3) {
        num_nodes++;
    }
    fclose(fn);

    FILE *fe = fopen("/home/user/edges.csv", "r");
    while (fscanf(fe, "%d,%d,%[^\n]", &edges[num_edges].source_id, &edges[num_edges].target_id, edges[num_edges].relation_type) == 3) {
        num_edges++;
    }
    fclose(fe);

    // BUG: Implicit cross join, no filtering, no limit
    for (int i = 0; i < num_edges; i++) {
        for (int j = 0; j < num_edges; j++) {
            Node* n1 = get_node(edges[i].source_id);
            Node* n2 = get_node(edges[i].target_id);
            Node* n3 = get_node(edges[j].target_id);
            printf("%s -> %s -> %s\n", n1->name, n2->name, n3->name);
        }
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
