#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc jq
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/kg_edges.csv
Alice,WROTE,PaperA
Bob,WROTE,PaperA
Alice,AFFILIATED_WITH,UnivX
Bob,AFFILIATED_WITH,UnivX
Charlie,WROTE,PaperB
Dave,WROTE,PaperB
Charlie,AFFILIATED_WITH,UnivY
Dave,AFFILIATED_WITH,UnivY
Eve,WROTE,PaperC
Frank,WROTE,PaperC
Eve,AFFILIATED_WITH,UnivX
Frank,AFFILIATED_WITH,UnivX
Alice,WROTE,PaperD
Eve,WROTE,PaperD
Grace,WROTE,PaperA
Grace,AFFILIATED_WITH,UnivX
Heidi,WROTE,PaperE
Ivan,WROTE,PaperE
Heidi,AFFILIATED_WITH,UnivZ
Ivan,AFFILIATED_WITH,UnivZ
EOF

cat << 'EOF' > /home/user/find_pattern.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_EDGES 100
#define MAX_LEN 50

typedef struct {
    char subject[MAX_LEN];
    char relation[MAX_LEN];
    char object[MAX_LEN];
} Edge;

int main() {
    FILE *f = fopen("/home/user/kg_edges.csv", "r");
    if (!f) return 1;

    Edge edges[MAX_EDGES];
    int count = 0;
    char line[150];
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\n")] = 0;
        char *s = strtok(line, ",");
        char *r = strtok(NULL, ",");
        char *o = strtok(NULL, ",");
        if (s && r && o) {
            strcpy(edges[count].subject, s);
            strcpy(edges[count].relation, r);
            strcpy(edges[count].object, o);
            count++;
        }
    }
    fclose(f);

    // Buggy logic: doesn't check if papers are the same
    for (int i=0; i<count; i++) {
        for (int j=0; j<count; j++) {
            if (strcmp(edges[i].relation, "AFFILIATED_WITH") == 0 && 
                strcmp(edges[j].relation, "AFFILIATED_WITH") == 0 &&
                strcmp(edges[i].object, edges[j].object) == 0 &&
                strcmp(edges[i].subject, edges[j].subject) < 0) {

                // Finds *any* paper they wrote
                char p1[MAX_LEN] = "", p2[MAX_LEN] = "";
                for(int k=0; k<count; k++) {
                    if (strcmp(edges[k].subject, edges[i].subject) == 0 && strcmp(edges[k].relation, "WROTE") == 0) strcpy(p1, edges[k].object);
                    if (strcmp(edges[k].subject, edges[j].subject) == 0 && strcmp(edges[k].relation, "WROTE") == 0) strcpy(p2, edges[k].object);
                }

                if (strlen(p1) > 0 && strlen(p2) > 0) {
                    printf("Found: %s, %s, %s, %s (Inst: %s)\n", edges[i].subject, edges[j].subject, p1, p2, edges[i].object);
                }
            }
        }
    }
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
