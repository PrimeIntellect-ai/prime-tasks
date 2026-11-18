#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/main.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var curr *[3]int

	re1 := regexp.MustCompile(`^([0-9]+)\.([0-9]+)\.([0-9]+)$`)
	re2 := regexp.MustCompile(`^([0-9]+)\.([0-9]+)\.([0-9]+) \-\> ([0-9]+)\.([0-9]+)\.([0-9]+)$`)

	for scanner.Scan() {
		line := scanner.Text()
		line = strings.TrimRight(line, "\r\n")

		m1 := re1.FindStringSubmatch(line)
		if m1 != nil {
			v0, _ := strconv.Atoi(m1[1])
			v1, _ := strconv.Atoi(m1[2])
			v2, _ := strconv.Atoi(m1[3])
			V := [3]int{v0, v1, v2}

			if curr == nil {
				curr = &V
				fmt.Printf("INIT %s\n", line)
			} else {
				if V[0] > curr[0] || (V[0] == curr[0] && V[1] > curr[1]) || (V[0] == curr[0] && V[1] == curr[1] && V[2] > curr[2]) {
					var bump string
					if V[0] > curr[0] {
						bump = "MAJOR"
					} else if V[1] > curr[1] {
						bump = "MINOR"
					} else {
						bump = "PATCH"
					}
					curr = &V
					fmt.Printf("%s BUMP %s\n", bump, line)
				} else if V[0] < curr[0] || (V[0] == curr[0] && V[1] < curr[1]) || (V[0] == curr[0] && V[1] == curr[1] && V[2] < curr[2]) {
					fmt.Printf("DOWNGRADE REJECTED %s\n", line)
				} else {
					fmt.Printf("UNCHANGED %s\n", line)
				}
			}
			continue
		}

		m2 := re2.FindStringSubmatch(line)
		if m2 != nil {
			v1_0, _ := strconv.Atoi(m2[1])
			v1_1, _ := strconv.Atoi(m2[2])
			v1_2, _ := strconv.Atoi(m2[3])
			v2_0, _ := strconv.Atoi(m2[4])
			v2_1, _ := strconv.Atoi(m2[5])
			v2_2, _ := strconv.Atoi(m2[6])

			V1 := [3]int{v1_0, v1_1, v1_2}
			V2 := [3]int{v2_0, v2_1, v2_2}

			if V1[0] > V2[0] || (V1[0] == V2[0] && V1[1] > V2[1]) || (V1[0] == V2[0] && V1[1] == V2[1] && V1[2] >= V2[2]) {
				fmt.Printf("INVALID MIGRATION %s\n", line)
			} else {
				var bump string
				if V2[0] > V1[0] {
					bump = "MAJOR"
				} else if V2[1] > V1[1] {
					bump = "MINOR"
				} else {
					bump = "PATCH"
				}
				fmt.Printf("MIGRATE %s FROM %d.%d.%d TO %d.%d.%d\n", bump, V1[0], V1[1], V1[2], V2[0], V2[1], V2[2])
			}
			continue
		}

		fmt.Printf("SYNTAX ERROR: %s\n", line)
	}
}
EOF

    cd /tmp
    go build -ldflags="-s -w" -o /app/schema_migrator main.go
    chmod +x /app/schema_migrator
    rm -f /tmp/main.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
