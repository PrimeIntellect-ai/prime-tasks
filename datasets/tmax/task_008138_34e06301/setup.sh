#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/netmon

    cat << 'EOF' > /home/user/netmon/monitor.go
package main

import (
	"fmt"
	"net"
	"os"
)

func main() {
	// BUG: Hardcoded path instead of using NET_LOG_DIR
	logPath := "/tmp/status.log"

	status := "8080_CLOSED"
	conn, err := net.Dial("tcp", "127.0.0.1:8080")
	if err == nil {
		status = "8080_OPEN"
		conn.Close()
	}

	f, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	f.WriteString(fmt.Sprintf("STATUS: %s\n", status))
}
EOF

    cat << 'EOF' > /home/user/netmon/run.sh
#!/bin/bash
go run /home/user/netmon/monitor.go
EOF
    chmod +x /home/user/netmon/run.sh

    chmod -R 777 /home/user
