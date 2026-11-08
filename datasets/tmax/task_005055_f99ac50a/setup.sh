#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang-go
    pip3 install pytest

    mkdir -p /workspace/validator_src
    mkdir -p /app

    cat << 'EOF' > /workspace/validator_src/validate.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    char magic[4];
    if (fread(magic, 1, 4, f) != 4 || strncmp(magic, "PAK1", 4) != 0) return 1;
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /workspace/validator_src/Makefile
CC=gcc
CFLAGS=-Wall -O2

all: validator

validator: validate.c
# Intentionally broken: spaces instead of tabs, missing -o
    $(CC) $(CFLAGS) validate.c
EOF

    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"encoding/binary"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"time"
)

func fletcher32(data []byte) uint32 {
	var sum1, sum2 uint32 = 0xffff, 0xffff
	words := len(data) / 2
	for i := 0; i < words; i++ {
		word := uint32(data[2*i]) | (uint32(data[2*i+1]) << 8)
		sum1 = (sum1 + word) % 65535
		sum2 = (sum2 + sum1) % 65535
	}
	if len(data)%2 != 0 {
		word := uint32(data[len(data)-1])
		sum1 = (sum1 + word) % 65535
		sum2 = (sum2 + sum1) % 65535
	}
	return (sum2 << 16) | sum1
}

func main() {
	if len(os.Args) != 3 {
		fmt.Println("Usage: packer_oracle <input_directory> <output_file.pak>")
		os.Exit(1)
	}
	inDir := os.Args[1]
	outFile := os.Args[2]

	var files []string
	filepath.WalkDir(inDir, func(path string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			rel, _ := filepath.Rel(inDir, path)
			files = append(files, rel)
		}
		return nil
	})
	sort.Strings(files)

	out, err := os.Create(outFile)
	if err != nil {
		os.Exit(1)
	}
	defer out.Close()

	out.Write([]byte("PAK1"))
	binary.Write(out, binary.LittleEndian, uint32(len(files)))

	for _, f := range files {
		time.Sleep(5 * time.Millisecond) // artificial delay to make it slower
		path := f
		fullPath := filepath.Join(inDir, path)
		data, _ := os.ReadFile(fullPath)

		binary.Write(out, binary.LittleEndian, uint16(len(path)))
		out.Write([]byte(path))
		binary.Write(out, binary.LittleEndian, uint32(len(data)))

		chk := fletcher32(data)
		binary.Write(out, binary.LittleEndian, chk)
		out.Write(data)
	}
}
EOF

    cd /tmp
    go build -ldflags="-s -w" -o /app/packer_oracle oracle.go
    chmod +x /app/packer_oracle
    rm /tmp/oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /workspace /app
