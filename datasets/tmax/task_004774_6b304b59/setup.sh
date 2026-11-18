#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/main_correct.go
package main

import (
	"fmt"
	"io"
	"os"
)

func main() {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		panic(err)
	}
	hash := uint64(0)
	for i, b := range data {
		hash = (hash + (uint64(b) * uint64(i+1))) % 1000000007
	}
	fmt.Println(hash)
}
EOF

    cd /app
    go build -ldflags="-s -w" -o fxhash_legacy main_correct.go
    rm main_correct.go

    mkdir -p /home/user
    cd /home/user
    git init fxhash_repo
    cd fxhash_repo

    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"

    go mod init fxhash

    cat << 'EOF' > main.go
package main

import (
	"fmt"
	"io"
	"os"
)

func main() {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		panic(err)
	}
	hash := uint64(0)
	for i, b := range data {
		hash = (hash + (uint64(b) * uint64(i+1))) % 1000000007
	}
	fmt.Println(hash)
}
EOF

    git add go.mod main.go
    git commit -m "Initial commit: implement fxhash"

    echo "fxhash docs" > docs.md
    git add docs.md
    git commit -m "Add docs"

    cat << 'EOF' > main.go
package main

import (
	"fmt"
	"io"
	"os"
)

func main() {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		panic(err)
	}
	hash := uint64(0)
	for i, b := range data {
		hash = (hash + uint64(uint32(b)*uint32(i+1))) % 1000000007
	}
	fmt.Println(hash)
}
EOF
    git add main.go
    git commit -m "Optimize hash calculation with uint32"

    go get github.com/sirupsen/logrus@v1.8.1
    git add go.mod go.sum
    git commit -m "Add logrus dependency"

    echo "replace github.com/sirupsen/logrus => /nonexistent/path" >> go.mod
    git add go.mod
    git commit -m "Update dependencies"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
