#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/extracted
    cd /home/user

    cat << 'EOF' > generate_archive.go
package main

import (
	"bytes"
	"compress/zlib"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
)

func process(name, content string, corruptHash bool) string {
	var b bytes.Buffer
	w := zlib.NewWriter(&b)
	w.Write([]byte(content))
	w.Close()

	hexData := hex.EncodeToString(b.Bytes())

	h := sha256.New()
	h.Write([]byte(content))
	hash := hex.EncodeToString(h.Sum(nil))

	if corruptHash {
		hash = "0000000000000000000000000000000000000000000000000000000000000000"
	}

	return fmt.Sprintf("FILE:%s\nSHA256:%s\nSIZE:%d\n%s\n", name, hash, len(hexData), hexData)
}

func main() {
	f, _ := os.Create("dataset.txt")
	defer f.Close()

	f.WriteString("RSCH_ARCHIVE_V1\n")
	f.WriteString(process("sensor_A.csv", "timestamp,value\n1000,42.5\n1001,43.1\n", false))
	f.WriteString(process("sensor_B.csv", "timestamp,value\n2000,12.5\n2001,13.1\n", false))
	f.WriteString(process("sensor_C.csv", "timestamp,value\n3000,99.9\n3001,88.8\n", true))
}
EOF

    go run generate_archive.go
    rm generate_archive.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
