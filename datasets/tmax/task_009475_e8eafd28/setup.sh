#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang binutils
    pip3 install pytest

    mkdir -p /home/user/artifacts

    # 1. Create authorized_keys
    cat << 'EOF' > /home/user/artifacts/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user1@host
ssh-dss AAAAB3NzaC1kc3MAAACB... user2@host
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY... user3@host
ssh-dss AAAAB3NzaC1kc3MAAACB... user4@host
EOF

    # 2. Create file_perms.json
    cat << 'EOF' > /home/user/artifacts/file_perms.json
[
  {"path": "/opt/app/config.yml", "owner": "root", "mode": "0666"},
  {"path": "/usr/bin/ping", "owner": "root", "mode": "4755"},
  {"path": "/home/user/readme.txt", "owner": "user", "mode": "0644"},
  {"path": "/etc/shadow", "owner": "root", "mode": "0640"},
  {"path": "/tmp/shared_cache", "owner": "nobody", "mode": "0777"}
]
EOF

    # 3. Create vulnerable Go binary
    cat << 'EOF' > /home/user/sys_monitor_src.go
package main
import (
	"os"
	"os/exec"
)
func main() {
	target := os.Getenv("MONITOR_TARGET")
	if target == "" {
		target = "127.0.0.1"
	}
	// The vulnerable command string
	cmd := exec.Command("bash", "-c", "ping -c 4 -W 2 " + target)
	cmd.Run()
}
EOF
    cd /home/user && go build -o /home/user/artifacts/sys_monitor sys_monitor_src.go
    rm /home/user/sys_monitor_src.go

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
