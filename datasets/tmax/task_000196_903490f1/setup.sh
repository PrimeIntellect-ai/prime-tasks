#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl
    pip3 install pytest

    mkdir -p /home/user/manager/algo
    mkdir -p /home/user/manager/api
    mkdir -p /home/user/manager/artifacts

    # Create artifacts
    echo -n "HELLO" > /home/user/manager/artifacts/alpha.bin
    echo -n "WORLD!" > /home/user/manager/artifacts/beta.bin

    # Create algo.go
    cat << 'EOF' > /home/user/manager/algo/algo.go
package algo

// CalculateSignature computes the custom artifact signature
func CalculateSignature(data []byte) uint32 {
	// TODO: Implement the mathematical signature
	// sum of (byte_value * (index + 1)) modulo 1000003
	return 0
}
EOF

    # Create api.go
    cat << 'EOF' > /home/user/manager/api/api.go
package api

import (
	"encoding/json"
	"net/http"
)

type Server struct {
	Manifest map[string]uint32
}

func (s *Server) ManifestHandler(w http.ResponseWriter, r *http.Request) {
	// TODO: Serialize s.Manifest to JSON and write to w
	// Make sure to set Content-Type to application/json
}
EOF

    # Create main.go
    cat << 'EOF' > /home/user/manager/main.go
package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"

	"manager/algo"
	"manager/api"
)

func main() {
	manifest := make(map[string]uint32)
	dir := "artifacts"

	files, err := ioutil.ReadDir(dir)
	if err != nil {
		log.Fatal(err)
	}

	for _, file := range files {
		if !file.IsDir() && filepath.Ext(file.Name()) == ".bin" {
			data, err := ioutil.ReadFile(filepath.Join(dir, file.Name()))
			if err != nil {
				log.Fatal(err)
			}
			manifest[file.Name()] = algo.CalculateSignature(data)
		}
	}

	server := &api.Server{Manifest: manifest}
	http.HandleFunc("/manifest", server.ManifestHandler)

	fmt.Println("Server listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

    # Create broken build.sh
    cat << 'EOF' > /home/user/manager/build.sh
#!/bin/bash
# Broken build script
go mod init wrongname
go build -o server .
EOF
    chmod +x /home/user/manager/build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
