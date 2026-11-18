#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/data

    # Create test data
    echo "This is a test file with some words." > /home/user/project/data/file1.txt
    echo "Another file. Go concurrency is fun." > /home/user/project/data/file2.txt
    echo "Python multiprocessing or threading can replicate channels." > /home/user/project/data/file3.txt
    echo "Polyglot build systems." > /home/user/project/data/file4.txt

    cat << 'EOF' > /home/user/project/src/worker.go
package main

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

func worker(jobs <-chan string, results chan<- int, wg *sync.WaitGroup) {
	defer wg.Done()
	for path := range jobs {
		content, err := ioutil.ReadFile(path)
		if err == nil {
			words := strings.Fields(string(content))
			results <- len(words)
		}
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: worker <directory>")
		os.Exit(1)
	}
	dir := os.Args[1]

	files, err := ioutil.ReadDir(dir)
	if err != nil {
		fmt.Println("Error reading dir")
		os.Exit(1)
	}

	jobs := make(chan string, len(files))
	results := make(chan int, len(files))

	var wg sync.WaitGroup
	numWorkers := 3

	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go worker(jobs, results, &wg)
	}

	for _, f := range files {
		if strings.HasSuffix(f.Name(), ".txt") {
			jobs <- filepath.Join(dir, f.Name())
		}
	}
	close(jobs)

	go func() {
		wg.Wait()
		close(results)
	}()

	total := 0
	for count := range results {
		total += count
	}

	fmt.Printf("Total words: %d\n", total)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
