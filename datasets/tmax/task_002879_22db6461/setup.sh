#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > /home/user/workspace/processor.go
package main

import (
	"fmt"
	"io/ioutil"
	"strings"
)

func main() {
	// Read artifact.txt
	data, err := ioutil.ReadFile("artifact.txt")
	if err != nil {
		panic(err)
	}

	content := strings.TrimSpace(string(data))

	// TODO: 1. Reverse the +1 ASCII shift
	// TODO: 2. Base64 decode
	// TODO: 3. Evaluate as RPN

	var result int
	// ... implementation ...

	fmt.Printf("Result: %d\n", result)
}
EOF

    echo -n "NUVhOTCFTWZhPDCNOVxhODCVVWJhNUBhRSSF" > /home/user/workspace/artifact.txt
    cp /home/user/workspace/processor.go /home/user/workspace/processor.go.orig

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
