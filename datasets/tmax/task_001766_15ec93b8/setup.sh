#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app.c
#include <stdio.h>
#include <stdlib.h>

extern int solve_csp(int num_tasks, int num_workers, const int* conflicts, int num_conflicts, int* out_assignments);

int verify(int num_tasks, int num_workers, const int* conflicts, int num_conflicts, const int* assignments) {
    for (int i=0; i<num_tasks; ++i) {
        if (assignments[i] < 0 || assignments[i] >= num_workers) return 0;
    }
    for (int i=0; i<num_conflicts; ++i) {
        int u = conflicts[2*i];
        int v = conflicts[2*i+1];
        if (assignments[u] == assignments[v]) return 0;
    }
    return 1;
}

int main() {
    FILE* f = fopen("/home/user/output.txt", "w");
    if (!f) return 1;

    // Test 1: Solvable graph coloring (5 nodes, 3 colors/workers)
    int conflicts1[] = {0,1, 0,2, 1,2, 1,3, 2,3, 3,4};
    int assignments[5];
    int res1 = solve_csp(5, 3, conflicts1, 6, assignments);
    if (res1) {
        if (verify(5, 3, conflicts1, 6, assignments)) fprintf(f, "TEST1: VALID\n");
        else fprintf(f, "TEST1: INVALID_ASSIGNMENT\n");
    } else {
        fprintf(f, "TEST1: NO_SOLUTION\n");
    }

    // Test 2: Unsolvable (Complete graph K4 needs 4 workers, but only 3 provided)
    int conflicts2[] = {0,1, 0,2, 0,3, 1,2, 1,3, 2,3};
    int res2 = solve_csp(4, 3, conflicts2, 6, assignments);
    if (!res2) fprintf(f, "TEST2: CORRECT_NO_SOLUTION\n");
    else fprintf(f, "TEST2: WRONG_SOLUTION\n");

    fclose(f);
    return 0;
}
EOF

    chmod -R 777 /home/user
