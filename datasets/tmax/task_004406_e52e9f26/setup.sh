#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/sensors.csv
timestamp,sensor_id,temperature,notes
100,S1,20.0,"Start of
run"
120,S1,24.0,"OK"
110,S1,,"Missing
value"
130,S1,22.0,"End"
105,S2,15.0,"S2 start"
115,S2,15.5,"S2 ok"
EOF

cat << 'EOF' > /home/user/process.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	file, err := os.Open("/home/user/data/sensors.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	// Skip header
	scanner.Scan()

	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Split(line, ",")
		if len(parts) >= 3 {
			// Do something with parts...
			fmt.Println("Processed", parts[1])
		}
	}
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
