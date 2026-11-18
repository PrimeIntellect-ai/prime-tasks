#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang-go
    pip3 install pytest

    mkdir -p /app

    # Create oracle
    cat << 'EOF' > /app/oracle.go
package main

import (
	"fmt"
	"io"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	f, err := os.Open(os.Args[1])
	if err != nil {
		return
	}
	defer f.Close()
	f.Seek(44, 0)
	samples := make([]byte, 0)
	buf := make([]byte, 1024)
	for {
		n, err := f.Read(buf)
		if n > 0 {
			samples = append(samples, buf[:n]...)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return
		}
	}
	consecutiveZeros := 0
	for i := 0; i < len(samples); i++ {
		if samples[i] == 0 {
			consecutiveZeros++
			continue
		}
	}
	fmt.Printf("Zeros: %d\n", consecutiveZeros)
}
EOF
    cd /app
    go build -o oracle_audiostat oracle.go
    rm oracle.go

    # Create test signal
    python3 -c "
import struct
with open('/app/test_signal.wav', 'wb') as f:
    f.write(b'RIFF' + struct.pack('<I', 36 + 44100) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, 44100, 44100, 1, 8) + b'data' + struct.pack('<I', 44100))
    data = bytearray([128]*44100)
    for i in range(10000, 10500):
        data[i] = 0
    f.write(data)
"

    # Setup git repo
    mkdir -p /home/user/audiostat
    cd /home/user/audiostat
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    go mod init audiostat

    cat << 'EOF' > analyzer.go
package main

import (
	"fmt"
	"io"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	f, err := os.Open(os.Args[1])
	if err != nil {
		return
	}
	defer f.Close()
	f.Seek(44, 0)
	samples := make([]byte, 0)
	buf := make([]byte, 1024)
	for {
		n, err := f.Read(buf)
		if n > 0 {
			samples = append(samples, buf[:n]...)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return
		}
	}
	consecutiveZeros := 0
	for i := 0; i < len(samples); i++ {
		if samples[i] == 0 {
			consecutiveZeros++
			continue
		}
	}
	fmt.Printf("Zeros: %d\n", consecutiveZeros)
}
EOF

    git add .
    git commit -m "Initial commit"
    git tag v1.0.0

    for i in $(seq 1 72); do
        echo "// commit $i" >> analyzer.go
        git commit -am "Commit $i"
    done

    cat << 'EOF' > analyzer.go
package main

import (
	"fmt"
	"io"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		return
	}
	f, err := os.Open(os.Args[1])
	if err != nil {
		return
	}
	defer f.Close()
	f.Seek(44, 0)
	samples := make([]byte, 0)
	buf := make([]byte, 1024)
	for {
		n, err := f.Read(buf)
		if n > 0 {
			samples = append(samples, buf[:n]...)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return
		}
	}
	consecutiveZeros := 0
	i := 0
	for i < len(samples) {
		if samples[i] == 0 {
			consecutiveZeros++
			continue
		}
		i++
	}
	fmt.Printf("Zeros: %d\n", consecutiveZeros)
}
EOF
    git commit -am "Introduce bug"

    for i in $(seq 74 200); do
        echo "// commit $i" >> analyzer.go
        git commit -am "Commit $i"
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user /app
