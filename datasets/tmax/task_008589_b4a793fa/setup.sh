#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
with open('/home/user/input.dat', 'wb') as f:
    for i in range(10):
        f.write(f'ありがとう {i}\n'.encode('utf-8'))
    for i in range(15):
        f.write(f'こんにちは {i}\n'.encode('shift_jis'))
"

    cat << 'EOF' > /home/user/processor.go
package main

import (
	"bufio"
	"os"
	"sync"
)

func main() {
	file, err := os.Open("/home/user/input.dat")
	if err != nil {
		panic(err)
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)

	lines := make(chan []byte)
	var wg sync.WaitGroup

	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for line := range lines {
				os.Stdout.Write(line)
				os.Stdout.Write([]byte("\n"))
			}
		}()
	}

	for scanner.Scan() {
		b := make([]byte, len(scanner.Bytes()))
		copy(b, scanner.Bytes())
		lines <- b
	}
	// The bug is here: missing channel closure
	wg.Wait()
}
EOF

    chmod -R 777 /home/user
