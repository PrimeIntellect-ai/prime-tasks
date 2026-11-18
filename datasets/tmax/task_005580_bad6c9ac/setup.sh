#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build_env
    cd /home/user/build_env

    cat << 'EOF' > main.c
#include <stdio.h>

extern int resolve_deps(int matrix[5][5], int num_nodes, int start_node);

int main() {
    int matrix[5][5] = {
        {0, 1, 1, 0, 0},
        {0, 0, 0, 1, 0},
        {0, 0, 0, 1, 1},
        {0, 0, 0, 0, 1},
        {0, 0, 0, 0, 0}
    };

    int result = resolve_deps(matrix, 5, 0);
    printf("Resolved Dependencies: %d\n", result);
    return 0;
}
EOF

    cat << 'EOF' > resolver.go
package main

import "sync"

// Reference Go implementation for graph traversal
// Counts the total number of unique nodes reachable from the start_node (including start_node)
func ResolveDeps(matrix [][]int, numNodes int, startNode int) int {
	visited := make([]bool, numNodes)
	visited[startNode] = true

	ch := make(chan int, numNodes*numNodes)
	var wg sync.WaitGroup

	var traverse func(node int)
	traverse = func(node int) {
		defer wg.Done()
		for i := 0; i < numNodes; i++ {
			if matrix[node][i] == 1 {
				ch <- i
				// In a real concurrent scenario, visited check needs a mutex, 
				// but this is a simplified prototype.
				if !visited[i] {
					visited[i] = true
					wg.Add(1)
					go traverse(i)
				}
			}
		}
	}

	wg.Add(1)
	go traverse(startNode)
	wg.Wait()
	close(ch)

	count := 0
	for i := 0; i < numNodes; i++ {
		if visited[i] {
			count++
		}
	}
	return count
}
EOF

    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -Wextra

all: validator

validator: main.o
	$(CC) $(CFLAGS) -o validator main.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

clean:
	rm -f *.o validator
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
