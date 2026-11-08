#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang-go
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/main.c
#include <stdio.h>
#include <math.h>

int main() {
    printf("%f\n", sqrt(16.0));
    printf("%f\n", sqrt(25.0));
    printf("%f\n", sqrt(144.0));
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
all: main

main: main.o
	gcc -o main main.o

main.o: main.c
	gcc -c main.c
EOF

    cat << 'EOF' > /home/user/project/analyzer.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"sync"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var lines []string
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}

	results := make(chan string, len(lines))
	var wg sync.WaitGroup

	for _, line := range lines {
		wg.Add(1)
		go func(l string) {
			defer wg.Done()
			results <- fmt.Sprintf("Processed: %s", l)
		}(line)
	}

	wg.Wait()
	close(results)

	for r := range results {
		fmt.Println(r)
	}
}
EOF

    cat << 'EOF' > /home/user/project/expected.txt
Processed: 12.000000
Processed: 4.000000
Processed: 5.000000
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
