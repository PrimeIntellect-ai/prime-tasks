#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user/collatz

cat << 'EOF' > /home/user/collatz/main.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
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
	file, err := os.Open("/home/user/collatz/inputs.txt")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	out, err := os.Create("/home/user/collatz/output.txt")
	if err != nil {
		panic(err)
	}
	defer out.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		text := strings.TrimSpace(scanner.Text())
		if text == "" {
			continue
		}
		val, err := strconv.Atoi(text)
		if err != nil {
			continue
		}

		steps := collatzSteps(val)

		if steps == -1 {
			fmt.Fprintf(out, "Input: %d, Steps: Invalid\n", val)
		} else {
			fmt.Fprintf(out, "Input: %d, Steps: %d\n", val, steps)
		}
	}
}
EOF

cat << 'EOF' > /home/user/collatz/inputs.txt
12
15
-5
27
0
9
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
