#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/dataset_graph
cd /home/user/dataset_graph

cat << 'EOF' > graph_data.csv
D1,T1
D1,T2
D2,T2
D2,T3
D3,T1
D3,T4
D4,T1
D4,T2
D4,T3
D5,T5
D6,T4
D6,T5
D7,T1
D8,T2
D9,T3
D10,T4
EOF

cat << 'EOF' > analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_DATASETS 100
#define MAX_TAGS 100

char datasets[MAX_DATASETS][20];
char tags[MAX_TAGS][20];
int has_tag[MAX_DATASETS][MAX_TAGS] = {0};

int num_datasets = 0;
int num_tags = 0;

int get_dataset_idx(const char *name) {
    for (int i = 0; i < num_datasets; i++) {
        if (strcmp(datasets[i], name) == 0) return i;
    }
    strcpy(datasets[num_datasets], name);
    return num_datasets++;
}

int get_tag_idx(const char *name) {
    for (int i = 0; i < num_tags; i++) {
        if (strcmp(tags[i], name) == 0) return i;
    }
    strcpy(tags[num_tags], name);
    return num_tags++;
}

typedef struct {
    char name[20];
    int score;
} Result;

// Comparison function for sorting
int compare_results(const void *a, const void *b) {
    Result *r1 = (Result *)a;
    Result *r2 = (Result *)b;
    if (r1->score != r2->score) {
        return r2->score - r1->score; // Descending by score
    }
    return strcmp(r1->name, r2->name); // Ascending by name
}

int main() {
    FILE *fp = fopen("graph_data.csv", "r");
    if (!fp) {
        perror("Failed to open file");
        return 1;
    }

    char line[100];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\r\n")] = 0;
        char *d_str = strtok(line, ",");
        char *t_str = strtok(NULL, ",");
        if (d_str && t_str) {
            int d_idx = get_dataset_idx(d_str);
            int t_idx = get_tag_idx(t_str);
            has_tag[d_idx][t_idx] = 1;
        }
    }
    fclose(fp);

    Result results[MAX_DATASETS];

    // BUGGY LOGIC: Implicit cross join / overcounting
    for (int i = 0; i < num_datasets; i++) {
        strcpy(results[i].name, datasets[i]);
        int score = 0;
        for (int t = 0; t < num_tags; t++) {
            if (has_tag[i][t]) {
                for (int j = 0; j < num_datasets; j++) {
                    if (has_tag[j][t]) {
                        score++; // Counts self, and counts multiple shared tags multiple times
                    }
                }
            }
        }
        results[i].score = score;
    }

    // Sort results
    qsort(results, num_datasets, sizeof(Result), compare_results);

    // OUTPUT logic (Agent needs to write to file and limit to 5)
    FILE *out = fopen("top_datasets.txt", "w");
    for (int i = 0; i < num_datasets; i++) {
        fprintf(out, "%s:%d\n", results[i].name, results[i].score);
    }
    fclose(out);

    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
