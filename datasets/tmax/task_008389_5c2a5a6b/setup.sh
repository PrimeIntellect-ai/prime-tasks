#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang bubblewrap procps curl
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app

cat << 'EOF' > /home/user/app/server.go
package main

import (
	"fmt"
	"math/rand"
	"net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
	// Predictable token generation
	token := fmt.Sprintf("%x", rand.Int31())
	w.Write([]byte("Your token is: " + token))
}

func main() {
	http.HandleFunc("/", handler)
	http.ListenAndServe("127.0.0.1:8443", nil)
}
EOF

cd /home/user/app
go build -o server server.go

# Start the server when a shell is launched
echo "/home/user/app/server &" >> /home/user/.bashrc
echo "sleep 0.5" >> /home/user/.bashrc
echo "/home/user/app/server &" >> /etc/bash.bashrc
echo "sleep 0.5" >> /etc/bash.bashrc

chmod -R 777 /home/user
