#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind diffutils
    pip3 install pytest

    mkdir -p /home/user/math_port

    cat << 'EOF' > /home/user/math_port/mathops.h
#ifndef MATHOPS_H
#define MATHOPS_H

int* merge_and_sort(const int* arr1, int len1, const int* arr2, int len2, int* out_len);

#endif
EOF

    cat << 'EOF' > /home/user/math_port/mathops.c
#include <stdlib.h>
#include "mathops.h"

static int compare_ints(const void* a, const void* b) {
    return (*(int*)a - *(int*)b);
}

int* merge_and_sort(const int* arr1, int len1, const int* arr2, int len2, int* out_len) {
    *out_len = len1 + len2;
    int* result = (int*)malloc((*out_len) * sizeof(int));
    if (!result) return NULL;

    for (int i = 0; i < len1; i++) result[i] = arr1[i];
    for (int i = 0; i < len2; i++) result[len1 + i] = arr2[i];

    qsort(result, *out_len, sizeof(int), compare_ints);
    return result;
}
EOF

    cat << 'EOF' > /home/user/math_port/router.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mathops.h"

// Simple parser for URL parameters
void parse_seq(const char* param_str, int** arr, int* len) {
    char* str = strdup(param_str);
    char* token;
    int capacity = 10;
    *arr = (int*)malloc(capacity * sizeof(int));
    *len = 0;

    char* rest = str;
    while ((token = strtok_r(rest, ",", &rest))) {
        if (*len >= capacity) {
            capacity *= 2;
            *arr = (int*)realloc(*arr, capacity * sizeof(int));
        }
        (*arr)[(*len)++] = atoi(token);
    }
    // BUG: str is not freed. Agent must add: free(str);
}

void route_request(const char* url) {
    // Expected format: /math/merge?seq1=1,2,3&seq2=4,5,6
    if (strncmp(url, "/math/merge?", 12) == 0) {
        char* query = strdup(url + 12);
        char* seq1_str = NULL;
        char* seq2_str = NULL;

        char* rest = query;
        char* pair;
        while ((pair = strtok_r(rest, "&", &rest))) {
            if (strncmp(pair, "seq1=", 5) == 0) seq1_str = pair + 5;
            else if (strncmp(pair, "seq2=", 5) == 0) seq2_str = pair + 5;
        }

        if (seq1_str && seq2_str) {
            int *arr1, *arr2;
            int len1, len2;
            parse_seq(seq1_str, &arr1, &len1);
            parse_seq(seq2_str, &arr2, &len2);

            int out_len;
            int* result = merge_and_sort(arr1, len1, arr2, len2, &out_len);

#ifdef MINIMAL_CONTAINER
            printf("{\"result\": [");
            for (int i = 0; i < out_len; i++) {
                printf("%d%s", result[i], i < out_len - 1 ? ", " : "");
            }
            printf("]}\n");
#else
            printf("Merged and Sorted Sequence: ");
            for (int i = 0; i < out_len; i++) {
                printf("%d ", result[i]);
            }
            printf("\n");
#endif

            // BUG: arrays not freed. Agent must add:
            // free(arr1);
            // free(arr2);
            // free(result);
        }
        // BUG: query not freed. Agent must add: free(query);
    } else {
        printf("404 Not Found\n");
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <url>\n", argv[0]);
        return 1;
    }
    route_request(argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/expected_legacy.json
{"result": [1, 4, 8, 15, 16, 23, 42]}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
