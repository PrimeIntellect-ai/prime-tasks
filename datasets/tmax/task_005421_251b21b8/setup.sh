#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/collatz_sum.go
package main

import (
	"fmt"
	"os"
	"strconv"
	"sync"
)

func collatzSteps(n int) int {
	steps := 0
	for n != 1 {
		if n%2 == 0 {
			n = n / 2
		} else {
			n = 3*n + 1
		}
		steps++
	}
	return steps
}

func main() {
	if len(os.Args) != 3 {
		return
	}
	A, _ := strconv.Atoi(os.Args[1])
	B, _ := strconv.Atoi(os.Args[2])

	var wg sync.WaitGroup
	var mu sync.Mutex
	totalSteps := 0

	for i := A; i <= B; i++ {
		wg.Add(1)
		go func(num int) {
			defer wg.Done()
			steps := collatzSteps(num)
			mu.Lock()
			totalSteps += steps
			mu.Unlock()
		}(i)
	}

	wg.Wait()
	fmt.Println(totalSteps)
}
EOF

    chmod -R 777 /home/user
