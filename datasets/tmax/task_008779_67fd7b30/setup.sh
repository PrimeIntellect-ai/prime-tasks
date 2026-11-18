#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/projects/app1
    mkdir -p /home/user/projects/app2
    mkdir -p /home/user/projects/app3

    cat << 'EOF' > /home/user/projects/app1/main.go
package main
import "fmt"
func main() { fmt.Println("Hello") }
EOF

    cat << 'EOF' > /home/user/projects/app1/auth.go
package main
// SENSITIVE
var apiKey = "12345"
EOF

    cat << 'EOF' > /home/user/projects/app2/utils.go
package utils
func Helper() {}
EOF
    touch -d "3 days ago" /home/user/projects/app2/utils.go

    cat << 'EOF' > /home/user/projects/app2/config.json
{"env": "prod"}
EOF

    cat << 'EOF' > /home/user/projects/app3/handlers.go
package app3
func Handle() {}
EOF

    chown -R user:user /home/user/projects
    chmod -R 777 /home/user
