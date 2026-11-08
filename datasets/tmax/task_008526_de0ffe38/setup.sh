#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/auth-service
    cd /home/user/auth-service
    go mod init auth-service

    cat << 'EOF' > main.go
package main

// #cgo LDFLAGS: -L/opt/legacy/lib -llegacyauth
// #include <stdlib.h>
import "C"
import "fmt"

func main() {
	fmt.Println(GenerateToken("admin"))
}
EOF

    cat << 'EOF' > auth.go
package main

import (
	"fmt"
	"time"
)

var tokenCache = make(map[string]string)

func GenerateToken(user string) string {
	token := fmt.Sprintf("%s-%d", user, time.Now().UnixNano())
	// Intermittent race condition here
	tokenCache[user] = token
	return token
}
EOF

    cat << 'EOF' > auth_test.go
package main

import (
	"sync"
	"testing"
)

func TestGenerateToken(t *testing.T) {
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			GenerateToken("user")
		}(i)
	}
	wg.Wait()
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/auth-service
    chmod -R 777 /home/user
