#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ci_pipeline/monitor
    mkdir -p /home/user/ci_pipeline/processor
    mkdir -p /home/user/ci_pipeline/collector

    cat << 'EOF' > /home/user/ci_pipeline/run.sh
#!/bin/bash

mkdir -p /home/user/ci_pipeline/data
mkdir -p /home/user/ci_pipeline/artifacts
rm -f /home/user/ci_pipeline/data/store.log

echo "Building..."
cd /home/user/ci_pipeline/monitor && go build -o monitor
cd /home/user/ci_pipeline/processor && go build -o processor
cd /home/user/ci_pipeline/collector && go build -o collector

echo "Starting monitor..."
/home/user/ci_pipeline/monitor/monitor &
MONITOR_PID=$!

echo "Starting processor..."
/home/user/ci_pipeline/processor/processor &
PROCESSOR_PID=$!

sleep 2

echo "Running collector..."
if /home/user/ci_pipeline/collector/collector; then
    echo "Collector finished successfully."
    kill $PROCESSOR_PID
    kill $MONITOR_PID
    echo "PIPELINE PASSED" > /home/user/ci_pipeline/artifacts/pass.txt
    exit 0
else
    echo "Collector failed."
    kill $PROCESSOR_PID
    kill $MONITOR_PID
    exit 1
fi
EOF
    chmod +x /home/user/ci_pipeline/run.sh

    cat << 'EOF' > /home/user/ci_pipeline/monitor/main.go
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

func dirSize(path string) (int64, error) {
	var size int64
	err := filepath.Walk(path, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			size += info.Size()
		}
		return err
	})
	return size, err
}

func main() {
	for {
		size, err := dirSize("/home/user/ci_pipeline/data")
		if err == nil && size > 10*1024*1024 {
			fmt.Println("QUOTA EXCEEDED! Killing pipeline.")
			os.Exit(1)
		}
		time.Sleep(100 * time.Millisecond)
	}
}
EOF

    cat << 'EOF' > /home/user/ci_pipeline/processor/main.go
package main

import (
	"io"
	"net"
	"os"
)

func main() {
	listener, err := net.Listen("tcp", "127.0.0.1:9000")
	if err != nil {
		panic(err)
	}
	defer listener.Close()

	conn, err := listener.Accept()
	if err != nil {
		panic(err)
	}
	defer conn.Close()

	outFile, err := os.Create("/home/user/ci_pipeline/data/store.log")
	if err != nil {
		panic(err)
	}
	defer outFile.Close()

	io.Copy(outFile, conn)
}
EOF

    cat << 'EOF' > /home/user/ci_pipeline/collector/main.go
package main

import (
	"bytes"
	"fmt"
	"net"
	"os"
)

func main() {
	// BUG: Connecting to 9001 instead of 9000
	conn, err := net.Dial("tcp", "127.0.0.1:9001")
	if err != nil {
		fmt.Println("Connection failed:", err)
		os.Exit(1)
	}
	defer conn.Close()

	// Send 20MB of data
	data := bytes.Repeat([]byte("A"), 20*1024*1024)
	_, err = conn.Write(data)
	if err != nil {
		fmt.Println("Write failed:", err)
		os.Exit(1)
	}
}
EOF

    cd /home/user/ci_pipeline/monitor && go mod init monitor
    cd /home/user/ci_pipeline/processor && go mod init processor
    cd /home/user/ci_pipeline/collector && go mod init collector

    chmod -R 777 /home/user
