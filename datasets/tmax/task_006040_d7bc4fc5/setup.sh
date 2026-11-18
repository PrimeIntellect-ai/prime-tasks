#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/logs/crash.log
INFO: Starting up daemon...
INFO: Loading log configuration...
DEBUG: Connecting to local mock virtualization socket... OK
INFO: Initializing log rotation schedule...
panic: open /var/log/customdaemon/app.log: permission denied

goroutine 1 [running]:
main.main()
	/home/user/app/main.go:15 +0x1a0
EOF

    cat << 'EOF' > /home/user/app/main.go
package main

import (
	"fmt"
	"os"
)

const LogPath = "/var/log/customdaemon/app.log"

func main() {
	file, err := os.OpenFile(LogPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		panic(err)
	}
	defer file.Close()

	// Simulate log configuration and rotation init
	fmt.Println("Daemon initialized: Log rotation configured for", LogPath)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
