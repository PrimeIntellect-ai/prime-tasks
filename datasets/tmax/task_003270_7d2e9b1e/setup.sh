#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/math_utils.c
#include <stdlib.h>

struct PolyTerm {
    int coeff;
    int exp;
};

int compare(const void* a, const void* b) {
    return ((struct PolyTerm*)b)->exp - ((struct PolyTerm*)a)->exp;
}

void sort_and_merge(struct PolyTerm* terms, int* n_terms) {
    if (*n_terms <= 0) return;
    qsort(terms, *n_terms, sizeof(struct PolyTerm), compare);

    int write_idx = 0;
    for (int i = 1; i < *n_terms; i++) {
        if (terms[i].exp == terms[write_idx].exp) {
            terms[write_idx].coeff += terms[i].coeff;
        } else {
            #ifdef CONDENSE_ZERO
            if (terms[write_idx].coeff == 0) {
                terms[write_idx] = terms[i];
                continue;
            }
            #endif
            write_idx++;
            terms[write_idx] = terms[i];
        }
    }

    #ifdef CONDENSE_ZERO
    if (terms[write_idx].coeff == 0) {
        write_idx--;
    }
    #endif

    *n_terms = write_idx + 1;
}
EOF

cat << 'EOF' > /home/user/poly_A.txt
5,10
-2,8
3,8
4,5
-4,5
7,2
1,0
EOF

cat << 'EOF' > /home/user/poly_B.txt
5,10
2,8
-1,8
6,4
7,2
2,0
EOF

cat << 'EOF' > /home/user/.expected_result.txt
-6,4
-1,0
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
