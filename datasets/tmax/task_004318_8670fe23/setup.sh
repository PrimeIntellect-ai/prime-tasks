#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/fast-det/src
    mkdir -p /home/user/fast-det/tests

    cat << 'EOF' > /home/user/fast-det/src/determinant.h
#ifndef DETERMINANT_H
#define DETERMINANT_H
int calculate_determinant(int size, double *matrix);
#endif
EOF

    cat << 'EOF' > /home/user/fast-det/src/determinant.c
#include "determinant.h"
#include <stdlib.h>
// BUG: Missing #include <math.h> for pow()

int calculate_determinant(int size, double *matrix) {
    if (size == 1) return matrix[0];
    if (size == 2) return matrix[0]*matrix[3] - matrix[1]*matrix[2];

    double det = 0;
    double *submatrix = malloc((size - 1) * (size - 1) * sizeof(double));

    for (int x = 0; x < size; x++) {
        int sub_i = 0;
        for (int i = 1; i < size; i++) {
            int sub_j = 0;
            for (int j = 0; j < size; j++) {
                if (j == x) continue;
                submatrix[sub_i * (size - 1) + sub_j] = matrix[i * size + j];
                sub_j++;
            }
            sub_i++;
        }
        det += pow(-1, x) * matrix[x] * calculate_determinant(size - 1, submatrix);
    }
    free(submatrix);
    return det;
}
EOF

    cat << 'EOF' > /home/user/fast-det/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include "determinant.h"

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    int size = atoi(argv[1]);
    double *matrix = malloc(size * size * sizeof(double));
    for (int i = 0; i < size * size; i++) {
        matrix[i] = atof(argv[2 + i]);
    }
    int det = calculate_determinant(size, matrix);
    printf("%d\n", det);
    free(matrix);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/fast-det/Makefile
CC=gcc
CFLAGS=-Wall -Werror

# BUG: Missing -lm, and target name is wrong
fast-det: src/main.o src/determinant.o
	$(CC) $(CFLAGS) -o fast-det src/main.o src/determinant.o

src/%.o: src/%.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f src/*.o fast-det
EOF

    cat << 'EOF' > /home/user/fast-det/tests/cases.csv
1,2,3 8 4 6,-14
2,3,6 1 1 4 -2 5 2 8 7,-306
3,2,1 0 0 1,1
EOF

    cat << 'EOF' > /home/user/fast-det/tests/test_runner.sh
#!/bin/bash
# BUGGY TEST RUNNER
PASSED=0
FAILED=0
TOTAL=0

# Bad CSV parsing loop
cat tests/cases.csv | while read line; do
    id=$(echo $line | cut -d',' -f1)
    size=$(echo $line | cut -d',' -f2)
    mat=$(echo $line | cut -d',' -f3)
    expected=$(echo $line | cut -d',' -f4)

    res=$(./fast-det $size $mat)

    if [ "$res" == "$expected" ]; then
        PASSED=$((PASSED+1))
    else
        FAILED=$((FAILED+1))
    fi
    TOTAL=$((TOTAL+1))
done

# Pipeline subshell issue prevents PASSED/FAILED from updating in parent shell
echo "{\"passed\": $PASSED, \"failed\": $FAILED, \"total\": $TOTAL}" > /home/user/pr_summary.json
EOF

    chmod +x /home/user/fast-det/tests/test_runner.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/fast-det
    chmod -R 777 /home/user
