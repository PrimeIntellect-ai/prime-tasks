#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang build-essential
    pip3 install pytest

    mkdir -p /home/user/artifact-builder
    mkdir -p /home/user/migrate
    mkdir -p /app

    # Create libextractor.c
    cat << 'EOF' > /home/user/artifact-builder/libextractor.c
#include <stdlib.h>
#include <string.h>

void parse_header(const char* src, int len, char* buffer) {
    for(int i=0; i<=len; i++) {
        buffer[i] = src[i];
    }
}
EOF

    # Create main.go
    cat << 'EOF' > /home/user/artifact-builder/main.go
package main

// #cgo LDFLAGS: -L. -lextractor
// #include "libextractor.c"
import "C"
import "fmt"

func main() {
    fmt.Println("Extractor running")
}
EOF

    # Create build.sh
    cat << 'EOF' > /home/user/artifact-builder/build.sh
#!/bin/bash
export CGO_LDFLAGS="-L/wrong/path"
go build -o extractor main.go
EOF
    chmod +x /home/user/artifact-builder/build.sh

    # Create dummy oracle
    cat << 'EOF' > /tmp/oracle.go
package main
import "fmt"
func main() {
    fmt.Println("oracle")
}
EOF
    go build -o /app/oracle_migrate /tmp/oracle.go
    rm /tmp/oracle.go

    # Create dummy video file
    touch /app/security_feed.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
