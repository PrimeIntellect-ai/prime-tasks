#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    # Create fake VNC server script
    cat << 'EOF' > /usr/local/bin/fake_vnc.py
import socket, time, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s.bind(('127.0.0.1', 5901))
    s.listen(1)
    while True:
        conn, addr = s.accept()
        conn.close()
except Exception:
    sys.exit(0)
EOF

    mkdir -p /home/user/app

    # Create the Go application
    cat << 'EOF' > /home/user/app/vnc-monitor.go
package main

import (
	"fmt"
	"net"
	"os"
)

func main() {
	lang := os.Getenv("LANG")
	tz := os.Getenv("TZ")
	vncPort := os.Getenv("QEMU_VNC_PORT")

	if lang != "C.UTF-8" {
		fmt.Println("FATAL: LANG environment variable must be exactly C.UTF-8 (got:", lang, ")")
		os.Exit(1)
	}

	if tz != "Etc/UTC" {
		fmt.Println("FATAL: TZ environment variable must be exactly Etc/UTC (got:", tz, ")")
		os.Exit(1)
	}

	if vncPort == "" {
		fmt.Println("FATAL: QEMU_VNC_PORT environment variable is missing")
		os.Exit(1)
	}

	target := fmt.Sprintf("127.0.0.1:%s", vncPort)
	conn, err := net.Dial("tcp", target)
	if err != nil {
		fmt.Printf("FATAL: Failed to connect to QEMU VNC at %s: %v\n", target, err)
		os.Exit(1)
	}
	defer conn.Close()

	successMsg := fmt.Sprintf("STATUS: OK | TZ: %s | LANG: %s | VNC_TARGET: %s", tz, lang, target)

	err = os.WriteFile("/home/user/app/status.log", []byte(successMsg+"\n"), 0644)
	if err != nil {
		fmt.Println("Failed to write log")
		os.Exit(1)
	}

	fmt.Println("Service started successfully.")
}
EOF

    # Create the systemd simulator script
    cat << 'EOF' > /home/user/app/systemd_sim.sh
#!/bin/bash
if [ ! -f /home/user/app/monitor.env ]; then
    echo "Error: /home/user/app/monitor.env not found"
    exit 1
fi

if [ ! -x /home/user/app/vnc-monitor ]; then
    echo "Error: Executable /home/user/app/vnc-monitor not found or not executable"
    exit 1
fi

# Simulate systemd EnvironmentFile
env -i bash -c "export \$(grep -v '^#' /home/user/app/monitor.env | xargs) && /home/user/app/vnc-monitor"
EOF

    chmod +x /home/user/app/systemd_sim.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
