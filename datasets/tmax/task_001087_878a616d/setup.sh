#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git golang-go iproute2 binutils
pip3 install pytest

mkdir -p /home/user
git init --bare /home/user/router_deploy.git

# Generate raw_routes.txt
for i in {0..255}; do
  echo "172.16.$i.0/24" >> /home/user/raw_routes.txt
done

# Create and compile router_daemon
mkdir -p /app
cat << 'EOF' > /app/router_daemon.go
package main

import (
	"net"
	"os"
	"os/exec"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		os.Exit(3)
	}
	addr, _ := net.ResolveUDPAddr("udp", "10.99.0.1:5000")
	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		os.Exit(1)
	}
	defer conn.Close()

	out, err := exec.Command("ip", "route").Output()
	if err != nil || !strings.Contains(string(out), "192.168.100.0/24") {
		os.Exit(2)
	}

	select {}
}
EOF

cd /app
go build -o router_daemon router_daemon.go
strip -s router_daemon
rm router_daemon.go

# Create start_daemon.sh
cat << 'EOF' > /home/user/start_daemon.sh
#!/bin/bash
# To be completed
EOF
chmod +x /home/user/start_daemon.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
