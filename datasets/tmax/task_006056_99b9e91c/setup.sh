#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /home/user/ci_cd_test
cd /home/user/ci_cd_test

cat << 'EOF' > pqueue.h
#ifndef PQUEUE_H
#define PQUEUE_H
void push(int val);
int pop();
#endif
EOF

cat << 'EOF' > pqueue.c
#include "pqueue.h"
#include <stdio.h>

#define MAX 100
int queue[MAX];
int size = 0;

void push(int val) {
    if (size < MAX) {
        queue[size++] = val;
    }
}

int pop() {
    if (size == 0) return -1;
    int max_idx = 0;
    for (int i = 1; i < size; i++) {
        if (queue[i] > queue[max_idx]) max_idx = i;
    }
    int val = queue[max_idx];
    for (int i = max_idx; i < size - 1; i++) queue[i] = queue[i+1];
    size--;
    return val;
}
EOF

cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pqueue.h"

int main(int argc, char *argv[]) {
    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "push", 4) == 0) {
            int val;
            sscanf(argv[i], "push %d", &val);
            push(val);
        } else if (strcmp(argv[i], "pop") == 0) {
            printf("%d ", pop());
        }
    }
    printf("\n");
    return 0;
}
EOF

# Broken Makefile (spaces instead of tabs)
cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-I.

pqueue_app: main.o pqueue.o
    $(CC) -o pqueue_app main.o pqueue.o

main.o: main.c
    $(CC) -c main.c $(CFLAGS)

pqueue.o: pqueue.c
    $(CC) -c pqueue.c $(CFLAGS)

clean:
    rm -f *.o pqueue_app
EOF

# Broken bash script (declare -a instead of -A for associative array)
cat << 'EOF' > run_tests.sh
#!/bin/bash

# BUG: this should be -A for associative array
declare -a test_cases

test_cases["push 5 push 10 pop"]="10 "
test_cases["push 1 pop pop"]="1 -1 "
test_cases["push 20 push 5 push 30 pop pop"]="30 20 "

for args in "${!test_cases[@]}"; do
    expected="${test_cases[$args]}"
    # Missing quotes around args will cause word splitting, but we actually want word splitting for passing to C app
    actual=$(./pqueue_app $args)
    if [ "$actual" == "$expected" ]; then
        echo "Test '$args' - PASS"
    else
        echo "Test '$args' - FAIL (Expected '$expected', got '$actual')"
    fi
done
EOF

chmod +x run_tests.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
