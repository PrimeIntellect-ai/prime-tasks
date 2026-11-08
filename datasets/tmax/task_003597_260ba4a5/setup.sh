#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc golang binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/calc_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct {
    int id;
    char op[10];
    double val;
    int in_degree;
    int *incoming;
    int incoming_count;
    double evaluated_val;
    int evaluated;
} Node;

int main() {
    int V, E;
    if (scanf("%d %d", &V, &E) != 2) return 1;

    Node *nodes = malloc(V * sizeof(Node));
    for (int i = 0; i < V; i++) {
        int id;
        scanf("%d", &id);
        nodes[id].id = id;
        scanf("%s", nodes[id].op);
        if (strcmp(nodes[id].op, "INPUT") == 0) {
            scanf("%lf", &nodes[id].val);
        }
        nodes[id].in_degree = 0;
        nodes[id].incoming = malloc(V * sizeof(int));
        nodes[id].incoming_count = 0;
        nodes[id].evaluated = 0;
    }

    for (int i = 0; i < E; i++) {
        int from, to;
        scanf("%d %d", &from, &to);
        nodes[to].incoming[nodes[to].incoming_count++] = from;
        nodes[to].in_degree++;
    }

    int evaluated_count = 0;
    while (evaluated_count < V) {
        for (int i = 0; i < V; i++) {
            if (!nodes[i].evaluated) {
                int can_evaluate = 1;
                for (int j = 0; j < nodes[i].incoming_count; j++) {
                    if (!nodes[nodes[i].incoming[j]].evaluated) {
                        can_evaluate = 0;
                        break;
                    }
                }

                if (can_evaluate) {
                    if (strcmp(nodes[i].op, "INPUT") == 0) {
                        nodes[i].evaluated_val = nodes[i].val;
                    } else if (strcmp(nodes[i].op, "ADD") == 0) {
                        double sum = 0.0;
                        for (int j = 0; j < nodes[i].incoming_count; j++) {
                            sum += nodes[nodes[i].incoming[j]].evaluated_val;
                        }
                        nodes[i].evaluated_val = sum;
                    } else if (strcmp(nodes[i].op, "MUL") == 0) {
                        double prod = 1.0;
                        for (int j = 0; j < nodes[i].incoming_count; j++) {
                            prod *= nodes[nodes[i].incoming[j]].evaluated_val;
                        }
                        nodes[i].evaluated_val = prod;
                    } else if (strcmp(nodes[i].op, "MAX") == 0) {
                        double mx = -999999.0;
                        for (int j = 0; j < nodes[i].incoming_count; j++) {
                            if (nodes[nodes[i].incoming[j]].evaluated_val > mx) {
                                mx = nodes[nodes[i].incoming[j]].evaluated_val;
                            }
                        }
                        nodes[i].evaluated_val = mx;
                    }
                    nodes[i].evaluated = 1;
                    evaluated_count++;
                }
            }
        }
    }

    for (int i = 0; i < V; i++) {
        printf("%d %.4f\n", i, nodes[i].evaluated_val);
    }

    return 0;
}
EOF

gcc -O3 /tmp/calc_engine.c -o /app/calc_engine -lm
strip /app/calc_engine
chmod +x /app/calc_engine

useradd -m -s /bin/bash user || true
mkdir -p /home/user/engine
chmod -R 777 /home/user
