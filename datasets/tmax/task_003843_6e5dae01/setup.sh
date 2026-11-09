#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/raw_data/sales
    echo -e "id,amount\n1,100\n2,200" > /home/user/raw_data/sales/Q1.csv
    echo "<users><user>Alice</user></users>" > /home/user/raw_data/users.xml

    mkdir -p /app/vendored/fast-tar
    cat << 'EOF' > /app/vendored/fast-tar/Makefile
build:
	GOOS=darwin GOARCH=amd64 go build -o fast-tar main.go
EOF

    cat << 'EOF' > /app/vendored/fast-tar/main.go
package main

import (
	"archive/tar"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

func main() {
	out := flag.String("out", "", "output file")
	flag.Parse()
	if *out == "" || flag.NArg() == 0 {
		fmt.Println("Usage: fast-tar -out <output> <input_dir>")
		os.Exit(1)
	}
	inDir := flag.Arg(0)

	outFile, err := os.Create(*out)
	if err != nil {
		panic(err)
	}
	defer outFile.Close()

	tw := tar.NewWriter(outFile)
	defer tw.Close()

	filepath.Walk(inDir, func(file string, fi os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if fi.IsDir() {
			return nil
		}
		header, err := tar.FileInfoHeader(fi, fi.Name())
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(inDir, file)
		header.Name = rel
		if err := tw.WriteHeader(header); err != nil {
			return err
		}
		f, err := os.Open(file)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = io.Copy(tw, f)
		return err
	})
}
EOF

    cd /app/vendored/fast-tar
    go mod init fast-tar

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
