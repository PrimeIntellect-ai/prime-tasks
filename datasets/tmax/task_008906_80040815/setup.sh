#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go g++ sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user/project/data

    # Create dummy data files with exact sizes
    head -c 50 /dev/zero > /home/user/project/data/a.txt
    head -c 200 /dev/zero > /home/user/project/data/b.txt
    head -c 30 /dev/zero > /home/user/project/data/c.cpp
    head -c 10 /dev/zero > /home/user/project/data/d.txt

    # Create skeleton evaluator.cpp
    cat << 'EOF' > /home/user/project/evaluator.cpp
#include <string>
#include <iostream>
// Agent needs to create evaluator.h and include it

extern "C" {
    int evaluate_expression(const char* expr, const char* ext, int size) {
        std::string e(expr);
        std::string x(ext);

        bool is_txt = (x == ".txt");
        bool size_small = (size < 100);

        if (e.find("AND") != std::string::npos) {
            return (is_txt && size_small) ? 1 : 0;
        }
        return 0;
    }
}
EOF

    # Create skeleton main.go
    cat << 'EOF' > /home/user/project/main.go
package main

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	_ "github.com/mattn/go-sqlite3"
)

// TODO: Import C++ FFI using cgo

func main() {
	db, err := sql.Open("sqlite3", "/home/user/project/files.db")
	if err != nil {
		panic(err)
	}
	defer db.Close()

	// TODO: Complete Schema Migration to files_v2
	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS files_v1 (id INTEGER PRIMARY KEY, path TEXT)`)
	if err != nil {
		panic(err)
	}

	// TODO: Fix worker pool logic
	jobs := make(chan string, 10)
	var wg sync.WaitGroup

	for i := 0; i < 3; i++ {
		go func() {
			// Worker logic missing
		}()
	}

	err = filepath.Walk("/home/user/project/data", func(path string, info os.FileInfo, err error) error {
		if !info.IsDir() {
			jobs <- path
		}
		return nil
	})
	if err != nil {
		panic(err)
	}

	close(jobs)
	wg.Wait()
	fmt.Println("Done")
}
EOF

    # Initialize go module
    cd /home/user/project
    go mod init project
    go get github.com/mattn/go-sqlite3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
