#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang
    pip3 install pytest flask

    mkdir -p /home/user/src /home/user/release

    cat << 'EOF' > /home/user/src/fibo.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    long long a = 0, b = 1, c;
    if (n == 0) { printf("0\n"); return 0; }
    for (int i = 2; i <= n; i++) {
        c = a + b;
        a = b;
        b = c;
    }
    printf("%lld\n", b);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/prime.go
package main

import (
	"fmt"
	"os"
	"strconv"
)

func isPrime(num int) bool {
	if num <= 1 { return false }
	for i := 2; i*i <= num; i++ {
		if num%i == 0 { return false }
	}
	return true
}

func main() {
	if len(os.Args) != 2 { return }
	n, _ := strconv.Atoi(os.Args[1])
	count := 0
	i := 2
	for {
		if isPrime(i) {
			count++
			if count == n {
				fmt.Println(i)
				return
			}
		}
		i++
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
