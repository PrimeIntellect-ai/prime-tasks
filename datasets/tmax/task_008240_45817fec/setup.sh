#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/docs/sub
    mkdir -p /home/user/bin
    mkdir -p /home/user/logs

    # Create docs with DEPRECATED
    echo "This feature is DEPRECATED." > /home/user/docs/intro.md
    echo "Setup is DEPRECATED in v2." > /home/user/docs/setup.md
    echo "Another DEPRECATED text." > /home/user/docs/sub/advanced.md

    # Create ELF binary with specific Api symbols
    cat << 'EOF' > /home/user/backend_srv.go
package main
import "fmt"
import "C"

//export ApiGetUser
func ApiGetUser() {}
//export ApiDeleteUser
func ApiDeleteUser() {}
//export ApiUpdateSystem
func ApiUpdateSystem() {}
//export InternalFunction
func InternalFunction() {}

func main() {
    fmt.Println("Backend")
}
EOF

    cd /home/user
    go build -buildmode=c-shared -o /home/user/bin/backend_srv /home/user/backend_srv.go
    rm /home/user/backend_srv.go /home/user/bin/backend_srv.h

    # Create WAL file
    cat << 'EOF' > /home/user/logs/system.wal
BEGIN TX
TX_ID: 1001
AUTHOR: admin
AFFECTED_DOC: intro.md
END TX
BEGIN TX
TX_ID: 1005
AUTHOR: jsmith
AFFECTED_DOC: setup.md
END TX
BEGIN TX
TX_ID: 1009
AUTHOR: admin
AFFECTED_DOC: intro.md
END TX
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
