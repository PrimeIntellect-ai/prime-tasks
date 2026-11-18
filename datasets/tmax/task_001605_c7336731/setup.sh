#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang-go
    pip3 install pytest

    mkdir -p /home/user/polyglot/core
    mkdir -p /home/user/polyglot/worker

    cat << 'EOF' > /home/user/polyglot/core/compute.c
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

bool is_prime(int num) {
    if (num <= 1) return false;
    for (int i = 2; i * i <= num; i++) {
        if (num % i == 0) return false;
    }
    return true;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }
    int n = atoi(argv[1]);
    int sum = 0;
    // BUG: should be i <= n
    for (int i = 2; i < n; i++) {
        if (is_prime(i)) {
            sum += i;
        }
    }
    printf("%d\n", sum);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/polyglot/core/Makefile
compute: compute.c
    gcc -o comp compute.c -lm
EOF

    cat << 'EOF' > /home/user/polyglot/worker/main.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
)

func main() {
	inputData, err := ioutil.ReadAll(os.Stdin)
	if err != nil {
		panic(err)
	}

	var numbers []int
	if err := json.Unmarshal(inputData, &numbers); err != nil {
		panic(err)
	}

	results := make(map[string]int)

	// TODO: Use goroutines and channels to concurrently execute:
	// /home/user/polyglot/core/compute <num>
	// and populate the results map.

	output, _ := json.Marshal(results)
	fmt.Println(string(output))
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/polyglot
    chmod -R 777 /home/user
